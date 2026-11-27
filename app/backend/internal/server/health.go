package server

import (
	"context"

	"connectrpc.com/connect"

	armadarrv1 "github.com/antoine-bouteiller/armadarr/app/backend/internal/gen/armadarr/v1"
)

type healthServer struct{}

func (healthServer) Check(context.Context, *connect.Request[armadarrv1.CheckRequest]) (*connect.Response[armadarrv1.CheckResponse], error) {
	return connect.NewResponse(&armadarrv1.CheckResponse{Status: armadarrv1.Status_STATUS_OK}), nil
}
