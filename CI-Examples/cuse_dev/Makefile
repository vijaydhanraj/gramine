GRAMINEDIR ?= ../..
SGX_SIGNER_KEY ?= $(GRAMINEDIR)/Pal/src/host/Linux-SGX/signer/enclave-key.pem

ARCH_LIBDIR ?= /lib/$(shell $(CC) -dumpmachine)

ifeq ($(DEBUG),1)
GRAMINE_LOG_LEVEL = debug
CFLAGS += -O0 -ggdb3
else
GRAMINE_LOG_LEVEL = error
CFLAGS += -O2
endif

######################### CUSE DEV/ CUSE_CLIENT EXECUTABLES ###########################

all: cuse cuse_client cuse_client.manifest.sgx cuse_client.sig cuse_client.token

cuse: cuse.c
	$(CC) -Wall $< `pkg-config fuse3 --cflags --libs` -o $@

cuse_client: cuse_client.c
	$(CC) -Wall $< -o $@

########################### CLIENT CUSE MANIFEST ############################

cuse_client.manifest: cuse_client.manifest.template
	gramine-manifest \
		-Dlog_level=$(GRAMINE_LOG_LEVEL) \
		-Darch_libdir=$(ARCH_LIBDIR) \
		$< > $@

cuse_client.manifest.sgx: cuse_client.manifest cuse_client
	@test -s $(SGX_SIGNER_KEY) || \
	    { echo "SGX signer private key was not found, please specify SGX_SIGNER_KEY!"; exit 1; }
	gramine-sgx-sign \
		--key $(SGX_SIGNER_KEY) \
		--manifest $< \
		--output $@

cuse_client.sig: cuse_client.manifest.sgx

cuse_client.token: cuse_client.sig
	gramine-sgx-get-token --output $@ --sig $<

################################## CLEANUP ####################################

clean:
	$(RM) -r \
		*.token *.sig *.manifest.sgx *.manifest cuse cuse_client *.so *.so.* OUTPUT