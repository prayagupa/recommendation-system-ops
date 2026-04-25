#!/usr/bin/env python3
"""
Minimal recommendation model training script.
Uses TensorFlow Recommenders (TFRS) to train a two-tower retrieval model
on synthetic user-item interaction data.

In production (Vertex AI) this same script is packaged into a Docker image
and submitted as a CustomTrainingJob.
"""

import os
import logging
import json
from datetime import datetime

import numpy as np
import redis

# Suppress TF info/warning logs
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import tensorflow as tf
import tensorflow_recommenders as tfrs

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
)
log = logging.getLogger("recs.training")

# ────────────────────────────────────────────────────────────────
# Configuration from environment (injected by Terraform)
# ────────────────────────────────────────────────────────────────
FEATURE_STORE_HOST  = os.environ.get("FEATURE_STORE_HOST", "localhost")
FEATURE_STORE_PORT  = int(os.environ.get("FEATURE_STORE_PORT", 6379))
MODEL_OUTPUT_DIR    = os.environ.get("MODEL_OUTPUT_DIR", "/tmp/recs-model-registry")
MODEL_NAME          = os.environ.get("MODEL_NAME", "recs")
MODEL_VERSION       = os.environ.get("MODEL_VERSION", datetime.utcnow().strftime("%Y%m%d%H%M%S"))
EPOCHS              = int(os.environ.get("TRAIN_EPOCHS", 5))
EMBEDDING_DIM       = int(os.environ.get("EMBEDDING_DIM", 64))
BATCH_SIZE          = int(os.environ.get("BATCH_SIZE", 256))

MODEL_EXPORT_PATH   = os.path.join(MODEL_OUTPUT_DIR, "models", MODEL_NAME, MODEL_VERSION)
LOG_DIR             = os.path.join(MODEL_OUTPUT_DIR, "logs", MODEL_VERSION)
CHECKPOINT_DIR      = os.path.join(MODEL_OUTPUT_DIR, "checkpoints", MODEL_VERSION)


# ────────────────────────────────────────────────────────────────
# Synthetic data generation
# ────────────────────────────────────────────────────────────────
NUM_USERS = 1_000
NUM_ITEMS = 5_000
NUM_INTERACTIONS = 50_000

def generate_synthetic_data():
    log.info("Generating synthetic interaction data …")
    rng = np.random.default_rng(42)
    user_ids  = [f"user_{i}" for i in rng.integers(0, NUM_USERS, NUM_INTERACTIONS)]
    item_ids  = [f"item_{i}" for i in rng.integers(0, NUM_ITEMS, NUM_INTERACTIONS)]
    ratings   = rng.uniform(1, 5, NUM_INTERACTIONS).astype(np.float32)

    dataset = tf.data.Dataset.from_tensor_slices({
        "user_id":  user_ids,
        "item_id":  item_ids,
        "rating":   ratings,
    })
    return dataset, list(set(user_ids)), list(set(item_ids))


# ────────────────────────────────────────────────────────────────
# Feature store helpers
# ────────────────────────────────────────────────────────────────
def connect_feature_store() -> redis.Redis | None:
    try:
        r = redis.Redis(host=FEATURE_STORE_HOST, port=FEATURE_STORE_PORT, socket_connect_timeout=3)
        r.ping()
        log.info("Connected to feature store at %s:%d", FEATURE_STORE_HOST, FEATURE_STORE_PORT)
        return r
    except Exception as exc:
        log.warning("Feature store unavailable (%s) — proceeding without it", exc)
        return None


def seed_feature_store(r: redis.Redis, user_ids: list[str], item_ids: list[str]):
    """Write synthetic user/item metadata into Redis."""
    if r is None:
        return
    log.info("Seeding feature store …")
    pipe = r.pipeline(transaction=False)
    for uid in user_ids[:100]:   # seed a subset for demo
        pipe.hset(f"user:{uid}", mapping={"age_bucket": "25-34", "country": "US"})
    for iid in item_ids[:500]:
        pipe.hset(f"item:{iid}", mapping={"category": "electronics", "price_bucket": "mid"})
    pipe.execute()
    log.info("Feature store seeded.")


# ────────────────────────────────────────────────────────────────
# Two-Tower model definition (TFRS)
# ────────────────────────────────────────────────────────────────
class UserTower(tf.keras.Model):
    def __init__(self, user_ids: list[str], embedding_dim: int):
        super().__init__()
        self.embedding = tf.keras.Sequential([
            tf.keras.layers.StringLookup(vocabulary=user_ids, mask_token=None),
            tf.keras.layers.Embedding(len(user_ids) + 1, embedding_dim),
        ])

    def call(self, user_id):
        return self.embedding(user_id)


class ItemTower(tf.keras.Model):
    def __init__(self, item_ids: list[str], embedding_dim: int):
        super().__init__()
        self.embedding = tf.keras.Sequential([
            tf.keras.layers.StringLookup(vocabulary=item_ids, mask_token=None),
            tf.keras.layers.Embedding(len(item_ids) + 1, embedding_dim),
        ])

    def call(self, item_id):
        return self.embedding(item_id)


class TwoTowerRecsModel(tfrs.Model):
    def __init__(self, user_ids: list[str], item_ids: list[str], embedding_dim: int, items_dataset):
        super().__init__()
        self.user_tower = UserTower(user_ids, embedding_dim)
        self.item_tower = ItemTower(item_ids, embedding_dim)
        self.task = tfrs.tasks.Retrieval(
            metrics=tfrs.metrics.FactorizedTopK(
                candidates=items_dataset.batch(128).map(self.item_tower)
            )
        )

    def compute_loss(self, features, training=False):
        user_embeddings = self.user_tower(features["user_id"])
        item_embeddings = self.item_tower(features["item_id"])
        return self.task(user_embeddings, item_embeddings)


# ────────────────────────────────────────────────────────────────
# Training
# ────────────────────────────────────────────────────────────────
def train():
    log.info("TensorFlow version: %s", tf.__version__)
    log.info("GPUs available: %s", tf.config.list_physical_devices("GPU"))

    dataset, user_ids, item_ids = generate_synthetic_data()

    r = connect_feature_store()
    seed_feature_store(r, user_ids, item_ids)

    items_ds = tf.data.Dataset.from_tensor_slices(item_ids)
    model = TwoTowerRecsModel(user_ids, item_ids, EMBEDDING_DIM, items_ds)
    model.compile(optimizer=tf.keras.optimizers.Adagrad(learning_rate=0.1))

    train_ds = dataset.shuffle(10_000).batch(BATCH_SIZE).cache()

    os.makedirs(LOG_DIR, exist_ok=True)
    os.makedirs(CHECKPOINT_DIR, exist_ok=True)

    callbacks = [
        tf.keras.callbacks.TensorBoard(log_dir=LOG_DIR, update_freq="epoch"),
        tf.keras.callbacks.ModelCheckpoint(
            filepath=os.path.join(CHECKPOINT_DIR, "ckpt-{epoch:02d}"),
            save_weights_only=True,
        ),
        tf.keras.callbacks.EarlyStopping(monitor="loss", patience=2, restore_best_weights=True),
    ]

    log.info("Starting training — epochs=%d, batch_size=%d, embedding_dim=%d", EPOCHS, BATCH_SIZE, EMBEDDING_DIM)
    history = model.fit(train_ds, epochs=EPOCHS, callbacks=callbacks)

    # ── Export SavedModel ──────────────────────────────────────
    os.makedirs(MODEL_EXPORT_PATH, exist_ok=True)
    tf.saved_model.save(model, MODEL_EXPORT_PATH)
    log.info("Model saved to %s", MODEL_EXPORT_PATH)

    # Write metadata for the model registry
    metadata = {
        "model_name":    MODEL_NAME,
        "version":       MODEL_VERSION,
        "embedding_dim": EMBEDDING_DIM,
        "num_users":     len(user_ids),
        "num_items":     len(item_ids),
        "final_loss":    float(history.history["loss"][-1]),
        "trained_at":    datetime.utcnow().isoformat(),
    }
    with open(os.path.join(MODEL_EXPORT_PATH, "metadata.json"), "w") as f:
        json.dump(metadata, f, indent=2)

    log.info("Training complete. Metadata: %s", json.dumps(metadata, indent=2))
    return metadata


if __name__ == "__main__":
    train()
