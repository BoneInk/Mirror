#!/usr/bin/python3
import json, os, sys, time
kind = os.path.basename(sys.argv[0])
catalog_path = os.environ.get('MIRROR_CATALOG_FIXTURES')
catalog_query = ('--list-models' in sys.argv or 'models' in sys.argv or '--acp' in sys.argv or 'acp' in sys.argv or '--input-format' in sys.argv or ('--mode' in sys.argv and sys.argv[sys.argv.index('--mode') + 1] == 'rpc'))
if catalog_path and catalog_query:
    fixtures = json.load(open(catalog_path))
    def reply(value):
        raw = (json.dumps(value, ensure_ascii=False) + '\n').encode()
        split = raw.find('🪞'.encode()) + 1
        sys.stdout.buffer.write(raw[:split]);sys.stdout.buffer.flush();time.sleep(.01)
        sys.stdout.buffer.write(raw[split:]);sys.stdout.buffer.flush()
    if kind in ['cursor', 'qoder', 'opencode']:
        assert sys.stdin.read() == ''
        assert sys.argv[1:] == (['models'] if kind == 'opencode' else ['--list-models'])
        print(fixtures[kind], end='');sys.exit(0)
    request = json.loads(sys.stdin.readline())
    if kind == 'claude':
        assert '--safe-mode' in sys.argv and '--no-session-persistence' in sys.argv
        assert request['type'] == 'control_request' and request['request']['subtype'] == 'initialize'
        reply({'type':'control_response','response':{'request_id':request['request_id'],'subtype':'success','response':fixtures[kind]}})
    elif kind == 'pi':
        assert '--no-extensions' in sys.argv and '--no-session' in sys.argv
        assert request['type'] == 'get_available_models'
        reply({'type':'response','id':request['id'],'command':'get_available_models','success':True,'data':fixtures[kind]})
    else:
        assert request['method'] == 'initialize' and request['params']['clientCapabilities'] == {}
        reply({'jsonrpc':'2.0','id':request['id'],'result':{'protocolVersion':1}})
        request = json.loads(sys.stdin.readline())
        assert request['method'] == 'session/new' and request['params']['mcpServers'] == []
        reply({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':'metadata-only'}})
        reply({'jsonrpc':'2.0','id':'client-action','method':'fs/read_text_file','params':{'path':'/private'}})
        denied = json.loads(sys.stdin.readline());assert denied['error']['code'] == -32601
        reply({'jsonrpc':'2.0','id':request['id'],'result':fixtures[kind]})
    assert sys.stdin.read() == ''
    sys.exit(0)
prompt = sys.argv[-1] if kind == "cursor" else sys.stdin.read()
assert '"role":"user"' in prompt or '"role" : "user"' in prompt
assert 'Mirror' in prompt
kind = os.path.basename(sys.argv[0])
def emit(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)
if kind in ['claude', 'pi']:
    assert sys.argv[sys.argv.index('--model') + 1] == 'fixture-model'
    assert sys.argv[sys.argv.index('--effort' if kind == 'claude' else '--thinking') + 1] == 'high'
if kind in ['claude', 'codebuddy']:
    assert sys.argv[sys.argv.index('--tools') + 1] == ''
    assert '--strict-mcp-config' in sys.argv
    if kind == 'claude': assert '--safe-mode' in sys.argv
    emit({'type':'stream_event','event':{'delta':{'type':'text_delta','text':'你'}}})
    time.sleep(.02)
    emit({'type':'stream_event','event':{'delta':{'type':'text_delta','text':'好🪞'}}})
    emit({'type':'result','is_error':False,'result':'你好🪞'})
elif 'opencode' in kind:
    assert json.loads(os.environ['OPENCODE_CONFIG_CONTENT'])['permission'] == 'deny'
    emit({'type':'text','part':{'id':'answer','text':'你好🪞'}})
    emit({'type':'text','part':{'id':'answer','text':'你好🪞'}})
    emit({'type':'step_finish'})
elif 'pi' in kind:
    assert '--no-tools' in sys.argv and '--no-extensions' in sys.argv
    emit({'type':'message_update','assistantMessageEvent':{'type':'text_delta','delta':'你好'}})
    emit({'type':'message_end','message':{'role':'assistant','stopReason':'stop','content':[{'type':'text','text':'你好🪞'}]}})
elif kind in ['cursor', 'kimi', 'qoder']:
    if kind == 'cursor': assert '--mode=ask' in sys.argv
    if kind == 'kimi': assert '--quiet' in sys.argv and '--plan' in sys.argv
    if kind == 'qoder': assert sys.argv[sys.argv.index('--tools') + 1] == ''
    sys.stdout.write('你好🪞')
elif 'slow' in kind:
    print('开头', flush=True)
    time.sleep(30)
else:
    for byte in '你好🪞'.encode():
        sys.stdout.buffer.write(bytes([byte]));sys.stdout.buffer.flush();time.sleep(.001)
