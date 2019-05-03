## The lines below can be uncommented for debugging the make rules
#
# OLD_SHELL := $(SHELL)
# SHELL = $(warning Building $@$(if $<, (from $<))$(if $?, ($? newer)))$(OLD_SHELL)
#
# print-%:
# 	@echo $* = $($*)

.PHONY: build fmt test vet clean go_protos grafeas_go_v1alpha1 swagger_docs

SRC = $(shell find . -type f -name '*.go' -not -path "./vendor/*")
CLEAN := *~

default: build

.install.tools: .install.protoc-gen-go .install.grpc-gateway protoc/bin/protoc
	@touch $@

CLEAN += .install.protoc-gen-go .install.grpc-gateway
.install.protoc-gen-go:
	go get -u -v github.com/golang/protobuf/protoc-gen-go && touch $@

.install.grpc-gateway:
	go get -u -v github.com/grpc-ecosystem/grpc-gateway/protoc-gen-grpc-gateway github.com/grpc-ecosystem/grpc-gateway/protoc-gen-swagger && touch $@

build: fmt go_protos swagger_docs
	go build -v ./...

# http://golang.org/cmd/go/#hdr-Run_gofmt_on_package_sources
fmt:
	@gofmt -l -w $(SRC)

test: go_protos
	@go test -v ./...

vet: go_protos
	@go vet -composites=false ./...

protoc/bin/protoc:
	mkdir -p protoc
	curl https://github.com/google/protobuf/releases/download/v3.3.0/protoc-3.3.0-linux-x86_64.zip -o protoc/protoc.zip -L
	unzip protoc/protoc -d protoc

CLEAN += protoc proto/*/*_go_proto

GO_PROTO_DIRS := $(patsubst %.proto,%_go_proto/.done,$(wildcard proto/*/*.proto))

# v1alpha1 has a different codebase structure than v1beta1 and v1,
# so it's generated separately
go_protos: v1alpha1/proto/grafeas.pb.go $(GO_PROTO_DIRS)

PROTOC_CMD=protoc/bin/protoc -I ./ \
	-I vendor/github.com/grpc-ecosystem/grpc-gateway/third_party/googleapis \
	-I vendor/github.com/grpc-ecosystem/grpc-gateway \
	-I vendor/github.com/googleapis/googleapis

v1alpha1/proto/grafeas.pb.go: v1alpha1/proto/grafeas.proto .install.tools
	$(PROTOC_CMD) \
		--go_out=plugins=grpc:. \
		--grpc-gateway_out=logtostderr=true:. \
		--swagger_out=logtostderr=true:. \
		v1alpha1/proto/grafeas.proto

# Builds go proto packages from protos
# Example:
# 	$ make proto/v1/grafeas_go_proto
# 	Builds: proto/v1/grafeas_go_proto/grafeas.pb.go and proto/v1/grafeas_go_proto/grafeas.pb.gw.go
# 	Using: proto/v1/grafeas.proto
%_go_proto/.done: %.proto .install.tools
	$(PROTOC_CMD) \
		--go_out=plugins=grpc,paths=source_relative:. \
		--grpc-gateway_out=logtostderr=true,paths=source_relative:. \
		$<
	@mkdir -p $(@D)
	mv $*.pb.go $(@D)
	if [ -f $*.pb.gw.go ]; then mv $*.pb.gw.go $(@D); fi
	@touch $@

swagger_docs: proto/v1beta1/swagger/*.swagger.json

proto/v1beta1/swagger/%.swagger.json: proto/v1beta1/%.proto protoc/bin/protoc .install.tools
	$(PROTOC_CMD) --swagger_out=logtostderr=true:. $<
	mv $(<D)/*.swagger.json $@

gapic_v1:
	# Move the proto files to match the packages. Python requires the path and package to match.
	mkdir -p grafeas/v1
	cp -a proto/v1/*.proto grafeas/v1/
	# Ignore project.proto
	rm grafeas/v1/project.proto
	# Rewrite imports to the new location.
	sed -i "s#import \"proto/v1/\(.*\).proto#import \"grafeas/v1/\1.proto#" grafeas/v1/*.proto
	# Generate Python library using local patch.
	artman --local --config artman_grafeas_v1.yaml generate python_gapic
	# Generate libraries
	artman --config artman_grafeas_v1.yaml generate csharp_gapic
	artman --config artman_grafeas_v1.yaml generate go_gapic
	artman --config artman_grafeas_v1.yaml generate java_gapic
	artman --config artman_grafeas_v1.yaml generate nodejs_gapic
	artman --config artman_grafeas_v1.yaml generate php_gapic
	artman --config artman_grafeas_v1.yaml generate ruby_gapic

clean:
	go clean ./...
	rm -rf $(CLEAN)
