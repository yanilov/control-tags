test:
	cargo test

build-cli:
	cargo build -p cli --release

build-lambda:
	cargo lambda build -p retention-lambda --release --arm64 --output-format zip


# dbg builds
build-cli-dbg:
	cargo build -p cli
