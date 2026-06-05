# Run all unit tests inside the spec/ directory cleanly on Windows PowerShell
test:
	@nvim --headless \
		--cmd "set rtp+=$(CURDIR)/lua" \
		-c "PlenaryBustedDirectory spec/"

.PHONY: test
