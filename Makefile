SHELL=/bin/bash

baseUrl = https://raw.githubusercontent.com/BinaryBirds/github-workflows/refs/heads/main/scripts

check: symlinks language deps lint headers

breakage:
	curl -s $(baseUrl)/check-api-breakage.sh | bash

symlinks:
	curl -s $(baseUrl)/check-broken-symlinks.sh | bash

language:
	curl -s $(baseUrl)/check-unacceptable-language.sh | bash

deps:
	curl -s $(baseUrl)/check-local-swift-dependencies.sh | bash

lint:
	curl -s $(baseUrl)/run-swift-format.sh | bash

format:
	curl -s $(baseUrl)/run-swift-format.sh | bash -s -- --fix

docc-local:
	curl -s $(baseUrl)/generate-docc.sh | bash -s -- --local

run-docc:
	curl -s $(baseUrl)/run-docc-docker.sh | bash

docc-warnings:
	curl -s $(baseUrl)/check-docc-warnings.sh | bash

headers:
	curl -s $(baseUrl)/check-swift-headers.sh | bash

fix-headers:
	curl -s $(baseUrl)/check-swift-headers.sh | bash -s -- --fix


test-cert:
	rm -rf docker/mariadb/certificates && mkdir -p docker/mariadb/certificates && cd docker/mariadb/certificates && ../scripts/generate-certificates.sh

test:
	swift test --parallel

docker-test:
	docker build -t feather-mysql-database-tests . -f ./docker/tests/Dockerfile && docker run --rm feather-mysql-database-tests
