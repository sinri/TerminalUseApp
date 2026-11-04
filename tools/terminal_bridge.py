#!/usr/bin/env python3
"""Dependency-free terminal CLI and newline-delimited stdio MCP server."""
import argparse
import json
import os
import sys
import urllib.request
import urllib.parse
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
    with urllib.request.urlopen(req, timeout=None if body is not None else 10) as response:
        return json.load(response)


def tool(name, description, field=None):
    properties = {}
    if name != 'terminal_list':
        properties['terminal_id'] = {'type': 'string', 'description': 'Stable ID from terminal_list.'}
    if field:
        properties[field] = {'type': 'string'}
    return {'name': name, 'description': description, 'inputSchema': {
        'type': 'object', 'properties': properties, 'required': [field] if field else [],
        'additionalProperties': False}}


TOOLS = [
    tool('terminal_list', 'List open terminal tabs and their stable IDs.'),
    tool('terminal_read', 'Read terminal output. Poll after submitting a command.'),
    tool('terminal_run', 'Execute a shell command in this terminal by typing it and pressing Enter. Pass the command without a newline. Execution is asynchronous.', 'command'),
    tool('terminal_input', 'Send raw keystrokes for interactive programs. For shell commands use terminal_run.', 'text'),
    tool('terminal_interrupt', 'Send Ctrl+C to the foreground process.'),
]


def call(name, arguments):
    if name == 'terminal_list':
        return request('/terminals')
    target = arguments.get('terminal_id')
    if target is not None and not isinstance(target, str):
        raise ValueError('terminal_id must be a string')
    suffix = '' if target is None else '?' + urllib.parse.urlencode({'terminal_id': target})
    if name == 'terminal_read':
        return request('/terminal' + suffix)
    if name == 'terminal_run':
        command = arguments['command']
        if not isinstance(command, str) or not command.strip():
            raise ValueError('Expected a non-empty command')
        return request('/input' + suffix, {'text': command.rstrip('\r\n') + '\r'})
    if name == 'terminal_input':
        return request('/input' + suffix, {'text': arguments['text']})
    if name == 'terminal_interrupt':
        return request('/interrupt' + suffix, {})
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
                result = {'protocolVersion': '2024-11-05', 'capabilities': {'tools': {}}, 'serverInfo': {'name': 'terminal-use', 'version': '0.1.0'}, 'instructions': 'Use terminal_list to choose a stable terminal_id, read the terminal, execute shell commands with terminal_run, and poll terminal_read to verify results. Use terminal_input only for raw keystrokes. The user also operates this terminal.'}
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
    parser.add_argument('action', choices=['list', 'read', 'input', 'interrupt', 'mcp'])
    parser.add_argument('text', nargs='?', default='')
    parser.add_argument('--terminal-id')
    args = parser.parse_args()
    if args.action == 'mcp':
        serve()
    else:
        name = {'list': 'terminal_list', 'read': 'terminal_read', 'input': 'terminal_input', 'interrupt': 'terminal_interrupt'}[args.action]
        print(json.dumps(call(name, {'text': args.text, **({'terminal_id': args.terminal_id} if args.terminal_id else {})}), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
