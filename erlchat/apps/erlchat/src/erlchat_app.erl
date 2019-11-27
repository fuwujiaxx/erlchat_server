%%%-------------------------------------------------------------------
%% @doc erlchat public API
%% @end
%%%-------------------------------------------------------------------

-module(erlchat_app).
 
-behaviour(application).
 
%% Application callbacks
-export([
  start/2,
  stop/1,
  server_url/0
]).
 
-define(C_ACCEPTORS,  100).
%% ===================================================================
%% Application callbacks
%% ===================================================================
 
start(_StartType, _StartArgs) ->
    %%初始化保存用户连接信息
    ets:new(session , [public , named_table]),
    Routes    = routes(),
    Dispatch  = cowboy_router:compile(Routes),
    Port      = port(),
    SSL_PATH = ssl_path(),
    TransOpts = [{port, Port} ,
      {cacertfile , SSL_PATH ++ "/cowboy-ca.crt"},
      {certfile , SSL_PATH ++ "/server.crt"},
      {keyfile , SSL_PATH ++ "/server.key"}],
    ProtoOpts = #{env => #{dispatch => Dispatch}},
    {ok, _}   = cowboy:start_tls(https, TransOpts, ProtoOpts),
    erlchat_sup:start_link().
 
stop(_State) ->
    ok.
 
%% ===================================================================
%% Internal functions
%% ===================================================================
routes() ->
    [
       {'_', [
              {"/chat" , erlchat_handler , []},
              {"/card" , erlcard_handler , []},
              {"/test" , erltest_handler , []}
       ]}
    ].
 
port() ->
    case os:getenv("PORT") of
        false ->
            {ok, Port} = application:get_env(http_port),
            Port;
        Other ->
            list_to_integer(Other)
    end.

ssl_path() ->
    case os:getenv("SSL_PATH") of
        flase ->
          {ok , SSL_PATH} = application:get_env(ssl_path),
          SSL_PATH;
        _ ->
            ""
    end.

server_url() ->
    case os:getenv("SERVER_PATH") of
        false ->
          {ok , SERVER_PATH} = application:get_env(server_path),
          SERVER_PATH;
        _ ->
          ""
    end.

%% internal functions