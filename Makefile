.DEFAULT_GOAL := test
TOX = ''
.PHONY: help clean piptools requirements dev_requirements \
        doc_requirementsprod_requirements static shell test coverage \
        isort_check isort style lint quality pii_check validate \
        migrate html_coverage upgrade extract_translation dummy_translations \
        compile_translations fake_translations  pull_translations \
        push_translations start-devstack open-devstack  pkg-devstack \
        detect_changed_source_translations validate_translations \
        docker.build docker.push docker.build.push

define BROWSER_PYSCRIPT
import os, webbrowser, sys
try:
	from urllib import pathname2url
except:
	from urllib.request import pathname2url

webbrowser.open("file://" + pathname2url(os.path.abspath(sys.argv[1])))
endef
export BROWSER_PYSCRIPT
BROWSER := python3 -c "$$BROWSER_PYSCRIPT"

ifdef TOXENV
TOX := tox -- #to isolate each tox environment if TOXENV is defined
endif

# Generates a help message. Borrowed from https://github.com/pydanny/cookiecutter-djangopackage.
help: ## display this help message
	@echo "Please use \`make <target>\` where <target> is one of"
	@awk -F ':.*?## ' '/^[a-zA-Z]/ && NF==2 {printf "\033[36m  %-25s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort

clean: ## delete generated byte code and coverage reports
	find . -name '*.pyc' -delete
	coverage erase
	rm -rf assets
	rm -rf pii_report

piptools: ## install pinned version of pip-compile and pip-sync
	pip install -r requirements/pip-tools.txt

requirements: piptools dev_requirements ## sync to default requirements

dev_requirements: ## sync to requirements for local development
	pip-sync -q requirements/dev.txt

doc_requirements:
	pip-sync -q requirements/doc.txt

production-requirements: piptools ## install requirements for production
	pip-sync -q requirements/production.txt

static: ## generate static files
	python3 manage.py collectstatic --noinput

shell: ## run Django shell
	python3 manage.py shell

test: clean ## run tests and generate coverage report
	$(TOX)python3 -Wd -m pytest

# To be run from CI context
coverage: clean
	pytest --cov-report html
	$(BROWSER) htmlcov/index.html

isort_check: ## check that isort has been run
	isort --check-only --diff -rc enterprise_catalog/

isort: ## run isort to sort imports in all Python files
	isort --recursive --atomic enterprise_catalog/

style: ## run Python style checker
	pycodestyle enterprise_catalog *.py

lint: ## run Python code linting
	pylint --rcfile=pylintrc enterprise_catalog *.py

quality: style isort_check lint ## check code style and import sorting, then lint

pii_check: ## check for PII annotations on all Django models
	DJANGO_SETTINGS_MODULE=enterprise_catalog.settings.test \
	code_annotations django_find_annotations --config_file .pii_annotations.yml --lint --report --coverage

validate: test quality pii_check ## run tests, quality, and PII annotation checks

migrate: ## apply database migrations
	python3 manage.py migrate

html_coverage: ## generate and view HTML coverage report
	coverage html && open htmlcov/index.html

upgrade: export CUSTOM_COMPILE_COMMAND=make upgrade
upgrade: piptools ## update the requirements/*.txt files with the latest packages satisfying requirements/*.in
	# Make sure to compile files after any other files they include!
	pip-compile --upgrade -o requirements/pip-tools.txt requirements/pip-tools.in
	pip-compile --upgrade -o requirements/base.txt requirements/base.in
	pip-compile --upgrade -o requirements/quality.txt requirements/quality.in
	pip-compile --upgrade -o requirements/test.txt requirements/test.in
	pip-compile --upgrade -o requirements/doc.txt requirements/doc.in
	pip-compile --upgrade -o requirements/tox.txt requirements/tox.in
	pip-compile --upgrade -o requirements/dev.txt requirements/dev.in
	pip-compile --upgrade -o requirements/production.txt requirements/production.in
	grep -e "^django==" requirements/base.txt > requirements/django.txt
	sed '/^[dD]jango==/d' requirements/test.txt > requirements/test.tmp
	mv requirements/test.tmp requirements/test.txt

extract_translations: ## extract strings to be translated, outputting .mo files
	python3 manage.py makemessages -l en -v1 -d django
	python3 manage.py makemessages -l en -v1 -d djangojs

dummy_translations: ## generate dummy translation (.po) files
	cd enterprise_catalog && i18n_tool dummy

compile_translations: # compile translation files, outputting .po files for each supported language
	python3 manage.py compilemessages

fake_translations: ## generate and compile dummy translation files

pull_translations: ## pull translations from Transifex
	tx pull -af --mode reviewed

push_translations: ## push source translation files (.po) from Transifex
	tx push -s

start-devstack: ## run a local development copy of the server
	docker-compose --x-networking up

open-devstack: ## open a shell on the server started by start-devstack
	docker exec -it enterprise_catalog /edx/app/catalog/devstack.sh open

pkg-devstack: ## build the catalog image from the latest configuration and code
	docker build -t enterprise_catalog:latest -f docker/build/enterprise_catalog/Dockerfile git://github.com/edx/configuration

detect_changed_source_translations: ## check if translation files are up-to-date
	cd enterprise_catalog && i18n_tool changed

validate_translations: fake_translations detect_changed_source_translations ## install fake translations and check if translation files are up-to-date

# Docker commands below
# TODO curate

dev.build:
	docker build . --tag kdmccormick96/enterprise-catalog # TODO

dev.push: dev.build
	docker push kdmccormick96/enterprise-catalog # TODO

dev.build.push: dev.build dev.push # TODO

dev.provision:
	bash ./provision-catalog.sh

dev.init: dev.up dev.migrate

dev.makemigrations:
	docker exec -it enterprise.catalog.app bash -c 'cd /edx/app/enterprise_catalog/enterprise_catalog && python3 manage.py makemigrations'

dev.migrate: # Migrates databases. Application and DB server must be up for this to work.
	docker exec -it enterprise.catalog.app bash -c 'cd /edx/app/enterprise_catalog/enterprise_catalog && make migrate'

dev.up: # Starts all containers
	docker-compose up -d

dev.up.build:
	docker-compose up -d --build

dev.down: # Kills containers and all of their data that isn't in volumes
	docker-compose down

dev.destroy: dev.down #Kills containers and destroys volumes. If you get an error after running this, also run: docker volume rm portal-designer_designer_mysql
	docker volume rm enterprise-catalog_enterprise_catalog_mysql

dev.stop: # Stops containers so they can be restarted
	docker-compose stop

%-shell: ## Run a shell, as root, on the specified service container
	docker-compose exec -u 0 $* env TERM=$(TERM) bash

%-logs: ## View the logs of the specified service container
	docker-compose logs -f --tail=500 $*

attach:
	docker attach enterprise.catalog.app

docker_build:
	docker build . --target app -t "openedx/enterprise-catalog:latest"
	docker build . --target newrelic -t "openedx/enterprise-catalog:latest-newrelic"

travis_docker_auth:
	echo "$$DOCKER_PASSWORD" | docker login -u "$$DOCKER_USERNAME" --password-stdin

travis_docker_tag: docker_build
	docker build . --target app -t "openedx/enterprise-catalog:$$TRAVIS_COMMIT"
	docker build . --target newrelic -t "openedx/enterprise-catalog:$$TRAVIS_COMMIT-newrelic"

travis_docker_push: travis_docker_tag travis_docker_auth ## push to docker hub
	docker push "openedx/enterprise-catalog:latest"
	docker push "openedx/enterprise-catalog:$$TRAVIS_COMMIT"
	docker push "openedx/enterprise-catalog:latest-newrelic"
	docker push "openedx/enterprise-catalog:$$TRAVIS_COMMIT-newrelic"
