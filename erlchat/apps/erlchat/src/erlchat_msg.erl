%%%-------------------------------------------------------------------
%%% @author fu
%%% @copyright (C) 2019, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 19. 十一月 2019 14:57
%%%-------------------------------------------------------------------
-module(erlchat_msg).
-author("fu").

%% API
-export([loop/0]).

loop() ->
  receive
    {addMsg , Pid , FromUserId , ToUserId , Message , MsgType , Time} ->
      erlchat_data:add_tb_uchat_message(FromUserId , ToUserId , Message , MsgType , Time),
      TotalUnread = erlchat_data:totalUnread(ToUserId),
      UnRead = erlchat_data:unReadMsgNum(ToUserId , FromUserId , ToUserId),
      Res = #{msgType => <<"97">> , userid => FromUserId , unread => UnRead , totalUnread => TotalUnread},
      ResMsg = jsx:encode(Res),
      erlang:start_timer(1 , Pid , ResMsg);
    {applyMsg , Pid , UserId} ->
      try
        HistoryApplyJson =  maps:get(<<"responseBody">> , historyApply(UserId)),
        Res = #{msgType => <<"96">> , historyApplyArray => HistoryApplyJson},
        ResMsg = jsx:encode(Res),
        erlang:start_timer(1 , Pid , ResMsg)
      catch
        _:_ -> ok
      end
  end.


historyApply(UserId) ->
  Res = httpc:request(erlchat_data:server_url() ++ "/friend/historyApply?userid=" ++ UserId),
  case Res of
    {ok , {_,_,ResBody}}->
      jsx:decode(list_to_binary(ResBody) , [return_maps]);
    {error , Cause} ->
      Cause
  end.