module github.com/antoine-bouteiller/armadarr

go 1.27

ignore node_modules

require (
	connectrpc.com/connect v1.21.1
	connectrpc.com/connect/v2 v2.0.2
	google.golang.org/protobuf v1.36.12
)

tool (
	connectrpc.com/connect/cmd/protoc-gen-connect-go
	google.golang.org/protobuf/cmd/protoc-gen-go
)
