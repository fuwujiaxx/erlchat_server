-module(erlchat_handler).

-export([init/2]).
-export([websocket_init/1]).
-export([websocket_handle/2]).
-export([websocket_info/2]).

init(Req=#{pid := Pid} , Opts) ->
  %% 保存用户会话
  UserId = proplists:get_value(<<"userid">> , cowboy_req:parse_qs(Req)),
  case ets:member(session , UserId) of
    true ->
      PidSoc = proplists:get_value(UserId , ets:lookup(session , UserId)),
      ets:delete(session , PidSoc),
      ets:delete(session , UserId),
      ets:insert(session , {UserId , Pid}),
      ets:insert(session , {Pid , UserId});
    false ->
      ets:insert(session , {UserId , Pid}),
      ets:insert(session , {Pid , UserId})
  end,
  {cowboy_websocket, Req, Opts , #{
    idle_timeout => 24 * 60 * 60 * 1000}}.

websocket_init(State) ->
  UserId = proplists:get_value(self() , ets:lookup(session , self())),
  MsgData = jsx:encode(#{msgType => <<"100">> , record => erlchat_data:queryMsg(UserId)}),
  erlang:start_timer(1 , self() , MsgData),
  TotalUnread = erlchat_data:totalUnread(UserId),
  Res = #{msgType => <<"97">> , userid => UserId , unread => -99 , totalUnread => TotalUnread},
  ResMsg = jsx:encode(Res),
  erlang:start_timer(1 , self() , ResMsg),
  %%创建进程发送历史申请记录
  MsgPid = spawn(fun erlchat_msg:loop/0),
  MsgPid ! {applyMsg , self() ,  UserId},
  {[], State}.

websocket_handle({text, Msg}, State) ->
  case jsx:is_json(Msg) of
    true ->
      #{<<"fromUserId">> := FromUserId , <<"toUserId">> := ToUserId , <<"message">> := Message ,
          <<"msgType">> := MsgType} = jsx:decode(Msg , [return_maps]),

      if (MsgType =:= <<"0">>) or (MsgType =:= <<"1">>) ->
          Pid = proplists:get_value(ToUserId , ets:lookup(session , ToUserId)),
          FromUserInfo = maps:get(<<"responseBody">> , erlchat_user:userInfo(FromUserId)),
          ToUserInfo = maps:get(<<"responseBody">> , erlchat_user:userInfo(ToUserId)),
          Time = calendar:now_to_local_time(erlang:now()),
          #{<<"portrait">> := FromAvatar} = FromUserInfo,
          ToSendMessageMap = #{userid => FromUserId , touserid => ToUserId,  message => Message ,
            msgType => MsgType , fromAvatar => FromAvatar , fromUserInfo => FromUserInfo , toUserInfo => ToUserInfo , lastTime => erlchat_date:localTimeFormat(Time)},
          FromSendMessageMap = #{userid => FromUserId , touserid => ToUserId, message => Message , msgType => MsgType ,
            fromAvatar => FromAvatar, fromUserInfo => FromUserInfo , toUserInfo => ToUserInfo , lastTime => erlchat_date:localTimeFormat(Time)},
          ToSendMsg = jsx:encode(ToSendMessageMap),
          FromSendMsg = jsx:encode(FromSendMessageMap),

          %%创建进程写入数据库
          MsgPid = spawn(fun erlchat_msg:loop/0),
          MsgPid ! {addMsg , Pid ,  FromUserId , ToUserId , Message , MsgType , Time},

          case Pid =/= undefined of
            true ->

              %%判断是否发送给自己
              if FromUserId =/= ToUserId ->
                erlang:start_timer(1 , Pid , ToSendMsg);
                true ->
                  true
              end,
              {[{text , FromSendMsg}], State};
            false ->
              {[{text , FromSendMsg}], State}
          end;

      %%聊天对话框打开
      (MsgType =:= <<"98">>) ->
          Val = "user-" ++ binary_to_list(ToUserId) ++ "|" ++ binary_to_list(FromUserId),
          case ets:member(session , Val) of
              true ->
                ok;
              false ->
                ets:insert(session , {Val , 1})
          end,
          erlchat_data:updateMsgUnread(ToUserId , FromUserId , -1),
          TotalUnread = erlchat_data:totalUnread(FromUserId),
          Res = #{msgType => <<"97">> , userid => ToUserId , unread => 0 , totalUnread => TotalUnread},
          ResMsg = jsx:encode(Res),
          {[{text , ResMsg}] , State};

      %%聊天对话框关闭
      (MsgType =:= <<"99">>) ->
          Val = "user-" ++ binary_to_list(ToUserId) ++ "|" ++ binary_to_list(FromUserId),
          case ets:member(session , Val) of
            true ->
              ets:delete(session , Val);
            false ->
              ok
          end,
          {[], State};
      true ->
        {[], State}
      end;
    false ->
      {[], State}
  end;
websocket_handle(_Data, State) ->
  {[], State}.

websocket_info({timeout, _Ref, Msg}, State) ->
  %%erlang:start_timer(1000 , self() , <<"How' you doin'?">>),
  {[{text, Msg}], State};
websocket_info(_Info, State) ->
  {[], State}.