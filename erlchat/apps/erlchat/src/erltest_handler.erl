%%%-------------------------------------------------------------------
%%% @author fu
%%% @copyright (C) 2019, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 20. 十一月 2019 13:42
%%%-------------------------------------------------------------------
-module(erltest_handler).
-author("fu").

%% API
-export([init/2]).


%% 测试并发
init(Req0 , Opts) ->

  Req = cowboy_req:reply(200, #{
    <<"content-type">> => <<"text/plain">>
  }, <<"{\"success\": true}">> , Req0),
  {ok, Req, Opts}.
