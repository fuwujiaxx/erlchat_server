%%%-------------------------------------------------------------------
%% @doc erlchat public API
%% @end
%%%-------------------------------------------------------------------

-module(erlchat_app).
 
-behaviour(application).
 
%% Application callbacks
-export([start/2, stop/1]).
 
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
    TransOpts = [{port, Port}],
    ProtoOpts = #{env => #{dispatch => Dispatch}},
    {ok, _}   = cowboy:start_clear(http, TransOpts, ProtoOpts),
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

%% internal functions