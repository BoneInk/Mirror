#!/usr/bin/env python3
"""Deterministic stdio peer for Mirror's conversation lifecycle tests."""
import json
import os
import sys

thread = 'mirror-test-' + str(os.getpid())
turn = 0

def emit(value):
    data = (json.dumps(value, ensure_ascii=False) + '\n').encode()
    # Exercise JSONL framing even when a multibyte character is split across reads.
    for i in range(0, len(data), 7):
        sys.stdout.buffer.write(data[i:i + 7])
        sys.stdout.buffer.flush()

def event(method, **params):
    emit({'method': method, 'params': {'threadId': thread, **params}})

for line in sys.stdin:
    message = json.loads(line)
    method, rid = message.get('method'), message.get('id')
    params = message.get('params', {})
    result = {}
    if method == 'initialize':
        assert params['clientInfo']['name'] == 'mirror'
    elif method == 'account/read':
        result = {'account': {'type': 'chatgpt'}, 'requiresOpenaiAuth': True}
    elif method in ('thread/start', 'thread/resume'):
        if method == 'thread/start':
            assert params['sandbox'] == 'read-only' and params['approvalPolicy'] == 'never'
        if method == 'thread/resume':
            thread = params['threadId']
            turn = max(turn, 1)
        result = {'thread': {'id': thread}}
    elif method == 'turn/start':
        assert params['threadId'] == thread
        text = params['input'][0]['text']
        if 'Explain this' in text:
            assert params['effort'] == 'high'
        if 'FAIL_TEST' in text:
            emit({'id': rid, 'error': {'code': -1, 'message': 'Simulated failure'}})
            continue
        turn += 1
        tid = str(turn)
        event('turn/started', turn={'id': tid, 'status': 'inProgress'})
        emit({'id': rid, 'result': {'turn': {'id': tid}}})
        if 'HOLD_TEST' in text:
            continue
        reply = '已收到引用 👋' if turn == 1 else '继续回答：上下文仍在'
        event('item/agentMessage/delta', turnId=tid, itemId='answer-' + tid, delta=reply[:4])
        event('item/agentMessage/delta', turnId=tid, itemId='answer-' + tid, delta=reply[4:])
        event('item/completed', turnId=tid, item={'id': 'answer-' + tid, 'type': 'agentMessage', 'text': reply})
        event('turn/completed', turn={'id': tid, 'status': 'completed', 'error': None})
        continue
    elif method == 'turn/interrupt':
        event('turn/completed', turn={'id': str(turn), 'status': 'interrupted', 'error': None})
    elif method == 'test/pending':
        continue
    if rid is not None:
        emit({'id': rid, 'result': result})
