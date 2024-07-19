.PHONY: slowsidecar
slowsidecar:
	@docker build -t zwindler/slow-sidecar slow-sidecar/

.PHONY: sidecaruser
sidecaruser:
	@docker build -t zwindler/sidecar-user sidecar-user/

.PHONY: docker-images
docker-images: slowsidecar sidecaruser

.PHONY:docker-push
docker-push: docker-images
	@docker push zwindler/slow-sidecar
	@docker push zwindler/sidecar-user