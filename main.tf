
locals {
  namespace               = "atlassian"
  license_key_secret_name = "confluence-license-secret"
  postgresql_secret_name  = "postgresql-secret-name"
}

variable "confluence_license_key" {
  type        = string
  default     = null
  description = "The Confluence license key"
}

variable "external_domain_name" {
  type        = string
  description = "The external domain name to add to host names"
}

resource "kubernetes_namespace_v1" "atlassian" {
  metadata {
    name = local.namespace
  }
}

resource "kubernetes_secret_v1" "confluence_license_secret" {
  depends_on = [kubernetes_namespace_v1.atlassian]
  metadata {
    name      = local.license_key_secret_name
    namespace = local.namespace
  }

  data = {
    "license-key" = var.confluence_license_key
  }

}

variable "postgresql_admin_password" {
  type        = string
  description = "PostgreSQL admin password"
}

variable "postgresql_database_name" {
  type        = string
  description = "PostgreSQL database name"
}


variable "postgresql_database_username" {
  type        = string
  description = "PostgreSQL database user"
}

variable "postgresql_database_password" {
  type        = string
  description = "PostgreSQL database password"
}

variable "postgresql_replication_password" {
  type        = string
  description = "PostgreSQL replication password"
}

resource "kubernetes_secret_v1" "postgresql_auth_secret" {
  depends_on = [kubernetes_namespace_v1.atlassian]
  metadata {
    name      = local.postgresql_secret_name
    namespace = local.namespace
  }

  data = {
    "postgres-password" : var.postgresql_admin_password
    "database-username" : var.postgresql_database_username
    "database-password" : var.postgresql_database_password
    "replication-password" : var.postgresql_replication_password
  }
}


resource "helm_release" "postgresql" {
  depends_on = [kubernetes_secret_v1.postgresql_auth_secret, kubernetes_namespace_v1.atlassian]
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "postgresql"
  version    = "12.1.6"
  name       = "postgresql-database"
  namespace  = local.namespace
  values     = [data.template_file.postgresql_values.rendered]

}

data "template_file" "postgresql_values" {
  template = file("${path.module}/postgresql/values.yaml")
  vars = {
    postgresql_secret_name       = local.postgresql_secret_name
    postgresql_database_username = var.postgresql_database_username
    postgresql_database_name     = var.postgresql_database_name
  }
}

resource "helm_release" "confluence" {
  depends_on = [helm_release.postgresql, kubernetes_namespace_v1.atlassian, kubernetes_secret_v1.confluence_license_secret]
  repository = "https://atlassian.github.io/data-center-helm-charts"
  version    = "1.8.1"
  chart      = "confluence"
  name       = "confluence-server"
  namespace  = local.namespace

  values = [data.template_file.confluence_values.rendered]
}

data "template_file" "confluence_values" {
  template = file("${path.module}/confluence/values.yaml")
  vars = {
    license_key_secret_name     = local.license_key_secret_name
    confluence_ingress_hostname = "confluence.${var.external_domain_name}"

    postgresql_secret_name       = local.postgresql_secret_name
    postgresql_database_username = var.postgresql_database_username
    postgresql_database_name     = var.postgresql_database_name
    postgresql_service_name      = "confluence-postgresql"
  }
}
