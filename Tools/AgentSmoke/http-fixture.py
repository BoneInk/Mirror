#!/usr/bin/python3
import http.server, json, sys, time
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def json(self, data):
        self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
        self.wfile.write(json.dumps({'code':0,'data':data}, ensure_ascii=False).encode())
    def catalog(self, data):
        self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
        self.wfile.write(json.dumps(data).encode())
    def do_GET(self):
        if self.path == '/catalog/api/agent/models':
            assert self.headers['x-auth-token'] == 'fixture-only'
            return self.catalog({'models':[{'id':'fixture::model','label':'Fixture','default':True}]})
        if self.path == '/catalog/models':
            assert self.headers['Authorization'] == 'Bearer fixture-only'
            return self.catalog({'data':[{'id':'model-a'},{'id':'model-a'},{'id':'model-b'}]})

        if self.path.startswith('/wb'):
            assert self.headers['Authorization'] == 'Bearer fixture-only'
            if self.path.endswith('/localassistant'): return self.json({'online': 'offline' not in self.path})
            assert 'message_id=fixture-message' in self.path
            messages = [{'message_id':'reply','role':'assistant','msg_type':'text','content':['你好🪞']}]
            if '/conflict/' in self.path: messages.append({'message_id':'other','role':'user','msg_type':'text','content':['other']})
            if '/permission/' in self.path: messages = [{'role':'assistant','msg_type':'permission_request'}]
            return self.json({'messages':messages})
        self.send_response(404);self.end_headers()
    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if self.path.startswith('/wb'):
            assert self.headers['Authorization'] == 'Bearer fixture-only'
            assert payload['msg_type'] == 'text' and 'Mirror' in payload['content']
            return self.json({'message_id':'fixture-message'})
        if '/api/agent/turns' in self.path:
            assert self.headers['x-auth-token'] == 'fixture-only'
            assert 'Mirror' in payload['prompt'] and '问题' in payload['prompt']
            assert payload['runtimeHint'] == {'namespace':'mirror','runtimeId':'reader','skillNames':[]}
            assert payload['modelProvider'] == 'fixture' and payload['model'] == 'model'
            assert 'threadId' not in payload
            self.send_response(200); self.send_header('Content-Type','text/event-stream');self.end_headers()
            events = [{'type':'thinking','content':'not an answer'}, {'type':'text','content':'你'}, {'type':'text','content':'好🪞'}]
            if '/truncated/' not in self.path:
                events.append({'type':'result','status':'failed' if '/fail/' in self.path else 'completed','output':'你好🪞'})
            for event in events:
                self.wfile.write(('data: '+json.dumps(event,ensure_ascii=False)+'\r\n\r\n').encode());self.wfile.flush()
            return
        assert payload['messages'][0]['role'] == 'system'
        assert payload['messages'][-1]['content'] == '问题🪞'
        assert payload['stream'] is True
        if self.path.startswith('/fail/'):
            self.send_response(401);self.end_headers();return
        if self.path.startswith('/redirect/'):
            self.send_response(307);self.send_header('Location','/v1/chat/completions');self.end_headers();return
        self.send_response(200)
        if self.path.startswith('/json/'):
            self.send_header('Content-Type', 'application/json'); self.end_headers()
            self.wfile.write(json.dumps({'choices':[{'message':{'content':'你好🪞'}}]}).encode());return
        self.send_header('Content-Type','text/event-stream');self.end_headers()
        for text in ['你','好🪞']:
            data = json.dumps({'choices':[{'delta':{'content':text},'finish_reason':None}]},ensure_ascii=False)
            self.wfile.write(('data: '+data.replace(', \"finish_reason\"', ',\n\"finish_reason\"').replace('\n', '\ndata: ')+'\n\n').encode());self.wfile.flush();time.sleep(.02)
        if not self.path.startswith('/truncated/'):
            self.wfile.write(b'data: [DONE]\n\n');self.wfile.flush()
server = http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
open(sys.argv[1],'w').write(str(server.server_port))
server.serve_forever()
