ENV ?= dev

create-cluster:
	@echo "Creating kind cluster for environment: $(ENV)"
	kind create cluster --name $(ENV)-services-amer --config $(ENV)/kind-cluster.yaml

delete-cluster:
	@echo "Deleting kind cluster for environment: $(ENV)"
	kind delete cluster --name $(ENV)-services-amer
