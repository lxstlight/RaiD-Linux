# RaiD Linux build system.
#
#   make packages   build the RaiD Linux .deb packages into out/debs
#   make iso        build the packages and the live ISO (needs root)
#   make update     build the packages and the offline update of RaiD Linux 1.0
#                   for a USB stick (out/RaiD-Linux-VERSION-update)
#   make release    the files of a GitHub release (out/github-release)
#   make test       boot the ISO in QEMU
#   make clean      remove build results (keeps the package cache)

VERSION  := $(shell cat VERSION)
OUT      := out
ISO      := $(OUT)/raid-linux-$(VERSION)-amd64.iso
PACKAGES := raid-base raid-artwork raid-tools calamares-settings-raid

all: iso

packages:
	./scripts/build-packages.sh $(OUT)/debs $(PACKAGES)

iso: packages
	./scripts/build-iso.sh $(OUT)/debs $(OUT)

update: packages
	./scripts/make-update.sh $(OUT)/debs $(OUT)

# Uses what "make iso" and "make update" built; see docs/github.md.
release:
	./scripts/make-release.sh $(OUT)

test:
	./scripts/test-iso.sh $(ISO)

clean:
	rm -rf $(OUT)

.PHONY: all packages iso update release test clean
