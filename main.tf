resource "kubernetes_namespace" "strimzi" {
  metadata {
    name = "strimzi"
  }
}

resource "kubernetes_namespace" "kafka" {
  metadata {
    name = "kafka"
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

resource "kubernetes_manifest" "kafka_cluster" {
  manifest = yamldecode( <<-EOF
    apiVersion: kafka.strimzi.io/v1beta2
    kind: Kafka
    metadata:
      name: kafka-default-cluster
      namespace: kafka
    spec:
      kafka:
        replicas: 3
        listeners:
          - name: plain
            port: 9092
            type: internal
            tls: false
        storage:
          type: jbod
          volumes:
          - id: 0
            type: persistent-claim
            size: 100Gi
            deleteClaim: false
        config:
          offsets.topic.replication.factor: 1
          transaction.state.log.replication.factor: 1
          transaction.state.log.min.isr: 1
          default.replication.factor: 3
          min.insync.replicas: 2
      zookeeper:
        replicas: 3
        storage:
          type: persistent-claim
          size: 100Gi
          deleteClaim: false
      entityOperator:
        topicOperator: {}
        userOperator: {}
    EOF
  )
}