terraform {
  required_version = ">= 1.6.0"

  required_providers {
    # Used for local Docker-based demo environment
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }

    # Used for GCP production deployment
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # For generating random resource suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # For local file generation (configs, etc.)
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
