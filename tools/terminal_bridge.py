#!/usr/bin/env python3
"""Dependency-free terminal CLI and newline-delimited stdio MCP server."""
import argparse
import json
import os
import sys
import urllib.request
from pathlib import Path


def request(path, body=None):
    url = os.environ['TERMINAL_USE_URL']
    if not url.startswith('http://127.0.0.1:'):
        raise ValueError('Expected a loopback terminal URL')
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url + path, data=data, headers={
        'Authorization': 'Bearer ' + os.environ['TERMINAL_USE_TOKEN'],
        'Content-Type': 'application/json',
    })
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.load(response)


TOOLS = [
    {'name': 'terminal_read', 'description': 'Read the shared terminal rendered screen and scrollback, process status, rows and columns. Commands are asynchronous; poll this after input.', 'inputSchema': {'type': 'object', 'properties': {}, 'additionalProperties': False}},
    {'name': 'terminal_input', 'description': 'Send exact text/keys to the shared PTY. Append \\r to submit a shell command. This has full local shell privileges. Check the terminal first.', 'inputSchema': {'type': 'object', 'properties': {'text': {'type': 'string'}}, 'required': ['text'], 'additionalProperties': False}},
    {'name': 'terminal_interrupt', 'description': 'Send Ctrl+C to the shared terminal foreground process.', 'inputSchema': {'type': 'object', 'properties': {}, 'additionalProperties': False}},
]


def call(name, arguments):
    if name == 'terminal_read':
        return request('/terminal')
    if name == 'terminal_input':
        return request('/input', {'text': arguments['text']})
    if name == 'terminal_interrupt':
        return request('/interrupt', {})
    raise ValueError('Unknown tool: ' + name)


def record_status(event):
    path = os.environ.get('TERMINAL_USE_MCP_STATUS')
    if path:
        # Only a readiness marker: never write terminal output or credentials.
        Path(path).write_text(json.dumps({'event': event}), encoding='utf-8')


def serve():
    for line in sys.stdin:
        message = None
        try:
            message = json.loads(line)
            if 'id' not in message:
                continue
            method = message.get('method')
            if method == 'initialize':
                result = {'protocolVersion': '2024-11-05', 'capabilities': {'tools': {}}, 'serverInfo': {'name': 'terminal-use', 'version': '0.1.0'}, 'instructions': 'Use terminal_read, terminal_input and terminal_interrupt for the shared terminal. Read before acting. Append a carriage return (\\r) to submit a command; poll terminal_read to check results. The user also operates this terminal.'}
                record_status('initialized')
            elif method == 'ping':
                result = {}
            elif method == 'tools/list':
                result = {'tools': TOOLS}
                record_status('tools_listed')
            elif method == 'tools/call':
                params = message['params']
                try:
                    output = call(params['name'], params.get('arguments', {}))
                    result = {'content': [{'type': 'text', 'text': json.dumps(output, ensure_ascii=False)}]}
                except Exception as exc:
                    result = {'isError': True, 'content': [{'type': 'text', 'text': str(exc)}]}
            else:
                print(json.dumps({'jsonrpc': '2.0', 'id': message['id'], 'error': {'code': -32601, 'message': 'Method not found'}}), flush=True)
                continue
            print(json.dumps({'jsonrpc': '2.0', 'id': message['id'], 'result': result}), flush=True)
        except Exception as exc:
            print(json.dumps({'jsonrpc': '2.0', 'id': message.get('id') if isinstance(message, dict) else None, 'error': {'code': -32603, 'message': str(exc)}}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['read', 'input', 'interrupt', 'mcp'])
    parser.add_argument('text', nargs='?', default='')
    args = parser.parse_args()
    if args.action == 'mcp':
        serve()
    else:
        name = {'read': 'terminal_read', 'input': 'terminal_input', 'interrupt': 'terminal_interrupt'}[args.action]
        print(json.dumps(call(name, {'text': args.text}), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
