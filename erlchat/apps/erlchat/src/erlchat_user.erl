%%%-------------------------------------------------------------------
%%% @author fu
%%% @copyright (C) 2019, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. 十一月 2019 9:52
%%%-------------------------------------------------------------------
-module(erlchat_user).
-author("fu").

%% API
-export([userInfo/1]).

userInfo(UserId) ->
  Res = httpc:request(erlchat_app:server_url() ++ "/mine/userInfo?userid=" ++ UserId),
  case Res of
    {ok , {_,_,ResBody}}->
      jsx:decode(list_to_binary(ResBody) , [return_maps]);
    {error , Cause} ->
      Cause
  end.