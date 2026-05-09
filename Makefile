.POSIX:
.PHONY: all compile test lint clean purge
.SUFFIXES: .el .elc

RM = rm -f
EMACS = emacs
SRC = autosync-git.el
BYTEC = $(SRC)c

DEPS := cl-lib package-lint

PKGCACHE := $(abspath $(PWD)/package-cache)

# INIT_PACKAGES from package-lint (https://github.com/purcell/package-lint)
# Copyrights: Steve Purcell (https://github.com/purcell)
INIT_PACKAGES="(progn \
  (require 'package) \
  (setq package-user-dir \"$(PKGCACHE)\" \
        package-check-signature nil) \
  (push '(\"nongnu\" . \"https://elpa.nongnu.org/nongnu/\") package-archives) \
  (push '(\"gnu\" . \"https://elpa.gnu.org/packages/\") package-archives) \
  (package-initialize) \
  (dolist (pkg '(${DEPS})) \
    (unless (package-installed-p pkg) \
      (unless (assoc pkg package-archive-contents) \
        (package-refresh-contents)) \
      (package-install pkg))) \
  (unless package-archive-contents (package-refresh-contents)) \
  )"

BATCH = $(EMACS) -Q --batch --eval $(INIT_PACKAGES)

all: compile

compile: $(BYTEC)

test: $(BYTEC)
	@echo "Testing $<"
	$(BATCH) \
		-L . \
		-l autosync-git-tests.el \
		-f ert-run-tests-batch-and-exit

lint: $(SRC)
	@echo "Linting $<"
	$(BATCH) \
		-L . \
		--eval "(require 'package-lint)" \
		-f package-lint-batch-and-exit $<

purge: clean
	$(RM) -r $(PKGCACHE)

clean:
	$(RM) $(BYTEC)

README.md: .cache/make-readme-markdown.el $(SRC)
	$(EMACS) -Q --script $< <$(SRC) >$@

.cache/make-readme-markdown.el:
	mkdir .cache
	curl -L -o $@ https://raw.github.com/mgalgs/make-readme-markdown/master/make-readme-markdown.el

.el.elc:
	@echo "Compiling $<"
	@$(BATCH) \
		-L . \
		-f batch-byte-compile $<
