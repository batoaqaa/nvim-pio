# Run all unit tests inside the spec/ directory
test:
	@nvim --headless \
		--cmd "set rtp+=./lua" \
		-c "PlenaryBustedDirectory spec/"

.PHONY: test
