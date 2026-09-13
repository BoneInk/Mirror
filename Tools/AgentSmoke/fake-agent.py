#!/usr/bin/python3
import json, os, sys, time
kind = os.path.basename(sys.argv[0])
prompt = sys.argv[-1] if kind == "cursor" else sys.stdin.read()
assert '"role":"user"' in prompt or '"role" : "user"' in prompt
assert 'Mirror' in prompt
kind = os.path.basename(sys.argv[0])
def emit(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)
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
