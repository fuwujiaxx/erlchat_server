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
-export([sendCard/3]).
-export([accept/2]).
-export([reject/2]).
-export([encode/1]).

userInfo(UserId) ->
  Res = httpc:request(erlchat_data:server_url() ++ "/mine/userInfo?userid=" ++ binary_to_list(UserId)),
  case Res of
    {ok , {_,_,ResBody}}->
      jsx:decode(list_to_binary(ResBody) , [return_maps]);
    {error , Cause} ->
      Cause
  end.

sendCard(FromUserId , ToUserId , Remark) ->
  Url = erlchat_data:server_url() ++ "/friend/sendCard?suserid=" ++ binary_to_list(FromUserId) ++ "&tuserid=" ++ binary_to_list(ToUserId) ++ "&remark=" ++ binary_to_list(Remark),
  Res = httpc:request(Url),
  case Res of
    {ok , {_,_,ResBody}}->
      jsx:decode(list_to_binary(ResBody) , [return_maps]);
    {error , Cause} ->
      Cause
  end.

%% 接受请求
accept(Id , UserId) ->
  Url = erlchat_data:server_url() ++ "/friend/accept?id=" ++ binary_to_list(Id) ++ "&userid=" ++ binary_to_list(UserId),
  Res = httpc:request(Url),
  case Res of
    {ok , {_,_,ResBody}}->
      jsx:decode(list_to_binary(ResBody) , [return_maps]);
    {error , Cause} ->
      Cause
  end.

%% 拒绝请求
reject(Id , UserId) ->
  Url = erlchat_data:server_url() ++ "/friend/reject?id=" ++ binary_to_list(Id) ++ "&userid=" ++ binary_to_list(UserId),
  Res = httpc:request(Url),
  case Res of
    {ok , {_,_,ResBody}}->
      jsx:decode(list_to_binary(ResBody) , [return_maps]);
    {error , Cause} ->
      Cause
  end.

encode(S) when is_list(S) ->
  encode(unicode:characters_to_binary(S));
encode(<<C, Cs/binary>>) when C >= $a, C =< $z ->
  [C] ++ encode(Cs);
encode(<<C, Cs/binary>>) when C >= $A, C =< $Z ->
  [C] ++ encode(Cs);
encode(<<C, Cs/binary>>) when C >= $0, C =< $9 ->
  [C] ++ encode(Cs);
encode(<<C, Cs/binary>>) when C == $. ->
  [C] ++ encode(Cs);
encode(<<C, Cs/binary>>) when C == $- ->
  [C] ++ encode(Cs);
encode(<<C, Cs/binary>>) when C == $_ ->
  [C] ++ encode(Cs);
encode(<<C, Cs/binary>>) ->
  escape_byte(C) ++ encode(Cs);
encode(<<>>) ->
  "".

escape_byte(C) ->
  "%" ++ hex_octet(C).

hex_octet(N) when N =< 9 ->
  [$0 + N];
hex_octet(N) when N > 15 ->
  hex_octet(N bsr 4) ++ hex_octet(N band 15);
hex_octet(N) ->
  [N - 10 + $A].