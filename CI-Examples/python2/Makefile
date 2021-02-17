GRAMINEDIR ?= ../..
SGX_SIGNER_KEY ?= $(GRAMINEDIR)/Pal/src/host/Linux-SGX/signer/enclave-key.pem

ARCH_LIBDIR ?= /lib/$(shell $(CC) -dumpmachine)

ifeq ($(DEBUG),1)
GRAMINE_LOG_LEVEL = debug
else
GRAMINE_LOG_LEVEL = error
endif

.PHONY: all
all: python.manifest
ifeq ($(SGX),1)
all: python.manifest.sgx python.sig python.token
endif

python.manifest: python.manifest.template
	gramine-manifest \
		-Dlog_level=$(GRAMINE_LOG_LEVEL) \
		-Darch_libdir=$(ARCH_LIBDIR) \
		-Dentrypoint=$(realpath $(shell sh -c "command -v python3")) \
		$< >$@

python.manifest.sgx: python.manifest
	@test -s $(SGX_SIGNER_KEY) || \
		{ echo "SGX signer private key was not found, please specify SGX_SIGNER_KEY!"; exit 1; }
	gramine-sgx-sign \
		--key $(SGX_SIGNER_KEY) \
		--manifest $< \
		--output $@

python.sig: python.manifest.sgx

python.token: python.sig
	gramine-sgx-get-token --output $@ --sig $<

clean:
	rm -rf *.manifest *.manifest.sgx *.token *.sig
