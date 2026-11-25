import { Schema } from 'effect'
import { HttpApi, HttpApiEndpoint, HttpApiGroup } from 'effect/http-api'

/** HTTP contract shared by the server implementation and the browser client. */
export class Api extends HttpApi.make('armadarr')
  .add(HttpApiGroup.make('health').add(HttpApiEndpoint.get('check', '/health', { success: Schema.Struct({ status: Schema.Literal('ok') }) })))
  .prefix('/api') {}
