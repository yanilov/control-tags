test:
	cargo test

build-cli:
	cargo build -p retention-cli --release

build-lambda:
	cargo lambda build -p retention-lambda --release --arm64 --output-format zip
