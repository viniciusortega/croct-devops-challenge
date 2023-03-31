resource "kubernetes_namespace" "strimzi" {
  metadata {
    name = "strimzi"
  }
}

resource "kubernetes_namespace" "application" {
  metadata {
    name = "application"
  }
}


resource "helm_release" "strimzi" {
  chart      = "strimzi-kafka-operator"
  name       = "strimzi"
  namespace  = "strimzi"
  repository = "https://strimzi.io/charts/"
  version    = "0.34.0"
  values     = [yamlencode({
    resources = {
    requests = {
      memory = "512Mi"
      cpu    = "250m"
    }
    limits = {
      memory = "1536Mi"
      cpu    = "1000m"
    }
    }
 })]
}