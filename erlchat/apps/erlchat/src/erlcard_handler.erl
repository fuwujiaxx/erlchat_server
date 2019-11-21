%%%-------------------------------------------------------------------
%%% @author fu
%%% @copyright (C) 2019, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. 十一月 2019 16:44
%%%-------------------------------------------------------------------
-module(erlcard_handler).
-author("fu").

%% API
-export([init/2]).

%% 用户发送名片
init(Req0 , Opts) ->
  Query = cowboy_req:parse_qs(Req0),

  %%获取用户id
  TUserId = proplists:get_value(<<"tuserid">> , Query),

  %%获取用户信息
  UserInfo = proplists:get_value(<<"userinfo">> , Query),

  Pid = proplists:get_value(TUserId , ets:lookup(session , TUserId)),

  UserInfoJson = jsx:decode(UserInfo , [return_maps]),

  Msg = jsx:encode(#{userInfo => UserInfoJson , msgType => <<"2">>}),

  %%向此用户发送消息
  erlang:start_timer(1 , Pid , Msg),

  Req = cowboy_req:reply(200, #{
    <<"content-type">> => <<"text/plain">>
  }, <<"{\"success\": true}">> , Req0),
  {ok, Req, Opts}.