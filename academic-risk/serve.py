"""Local development HTTP interface: POST /predict and GET /health."""
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import argparse
import json
from pathlib import Path
from urllib.parse import urlparse
from predict import CourseRiskPredictor,DEFAULT_MODEL


def create_server(host='127.0.0.1',port=8000,model_path=DEFAULT_MODEL,allow_origin=None,alert_threshold=None):
    predictor=CourseRiskPredictor(model_path,alert_threshold)
    if allow_origin:
        parsed=urlparse(allow_origin)
        if parsed.scheme not in {'http','https'} or not parsed.netloc or parsed.path or parsed.query or parsed.fragment or '\r' in allow_origin or '\n' in allow_origin:
            raise ValueError('allow_origin must be an exact HTTP(S) origin, without a path')
    class Handler(BaseHTTPRequestHandler):
        def reply(self,status,payload):
            content=json.dumps(payload,allow_nan=False).encode('utf-8')
            self.send_response(status)
            self.send_header('Content-Type','application/json; charset=utf-8')
            self.send_header('Content-Length',str(len(content)))
            if allow_origin and self.headers.get('Origin')==allow_origin:
                self.send_header('Access-Control-Allow-Origin',allow_origin)
                self.send_header('Vary','Origin')
                self.send_header('Access-Control-Allow-Methods','POST, GET, OPTIONS')
                self.send_header('Access-Control-Allow-Headers','Content-Type')
            self.end_headers();self.wfile.write(content)

        def do_GET(self):
            if self.path=='/health':self.reply(200,{'ready':True,'model_count':1,'model':'course_risk.pt'})
            else:self.reply(404,{'error':'Unknown endpoint'})

        def do_POST(self):
            if self.path!='/predict':return self.reply(404,{'error':'Unknown endpoint'})
            if self.headers.get('Origin') and self.headers.get('Origin')!=allow_origin:
                return self.reply(403,{'error':'Browser origin is not enabled'})
            try:
                length=int(self.headers.get('Content-Length','0'))
                if not 0<length<=1_000_000:raise ValueError('JSON request size must be between 1 and 1000000 bytes')
                payload=json.loads(self.rfile.read(length).decode('utf-8'))
                result=predictor.predict_student(payload)
            except (ValueError,TypeError,KeyError) as error:
                return self.reply(400,{'error':str(error)})
            self.reply(200,result)

        def do_OPTIONS(self):
            if self.path!='/predict':return self.reply(404,{'error':'Unknown endpoint'})
            if not allow_origin or self.headers.get('Origin')!=allow_origin:
                return self.reply(403,{'error':'Browser origin is not enabled'})
            self.reply(200,{'allowed':True})

        def log_message(self,*args):pass

    return ThreadingHTTPServer((host,port),Handler)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',type=int,default=8000)
    parser.add_argument('--model',type=Path,default=DEFAULT_MODEL)
    parser.add_argument('--allow-origin',help='Exact development frontend origin, e.g. http://localhost:3000')
    parser.add_argument('--alert-threshold',type=float)
    args=parser.parse_args()
    server=create_server(port=args.port,model_path=args.model,allow_origin=args.allow_origin,alert_threshold=args.alert_threshold)
    print(f'One model loaded. Local API: http://127.0.0.1:{server.server_port}/predict',flush=True)
    try:server.serve_forever()
    except KeyboardInterrupt:pass
    finally:server.server_close()
