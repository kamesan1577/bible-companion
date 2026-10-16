.PHONY: doctor setup check data swift build ios-ui ios-device source-audit
# Override PYTHON only when Python 3 is not on PATH. No global tool installation.
PYTHON ?= python3
doctor setup check data swift:
	$(PYTHON) scripts/harness/run.py $@
build:
	$(PYTHON) scripts/harness/run.py ios-build
ios-device:
	$(PYTHON) scripts/harness/run.py ios-device
ios-ui:
	$(PYTHON) scripts/harness/run.py ios-ui
source-audit:
	$(PYTHON) scripts/harness/run.py audit-source
