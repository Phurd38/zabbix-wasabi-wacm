#!/usr/bin/env python3
"""Build the Zabbix template from its sources.

Two things happen here:

1. `src/collect.js` is inlined into the master item, indented to fit the YAML
   block scalar. Keeping the collector in a real .js file makes it reviewable,
   diffable and lintable instead of buried in 70 kB of YAML.

2. Symbolic ids of the form `@@kind|identity@@` are replaced by UUIDs. Zabbix
   matches objects on import by UUID, not by name: reusing the UUIDs already
   present in the published template is what makes an update non-destructive,
   keeping item history intact. New objects get a fresh UUID.

Usage:
    python src/build.py
"""

import io
import os
import re
import sys
import uuid

try:
    import yaml
except ImportError:
    sys.exit('PyYAML is required: pip install pyyaml')

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

SOURCE = os.path.join(HERE, 'template.src.yaml')
OUTPUT = os.path.join(ROOT, 'template', 'wasabi_wacm_connect_by_http.yaml')

INJECT = re.compile(r'( *)@@INJECT:([^@]+)@@')
SYMBOL = re.compile(r'@@([^@]+)@@')


def inline_sources(text):
    """Replace @@INJECT:path@@ with the file content, preserving indentation."""

    def substitute(match):
        indent, relative = match.group(1), match.group(2)
        path = os.path.join(ROOT, relative)
        body = io.open(path, encoding='utf-8').read().rstrip('\n')
        lines = [indent + line if line.strip() else '' for line in body.split('\n')]
        return '\n'.join(lines)

    return INJECT.sub(substitute, text)


def index_published(path):
    """identity -> uuid, for every object of the currently published template."""
    if not os.path.exists(path):
        print('No published template found: every UUID will be new.')
        return {}

    root = yaml.safe_load(io.open(path, encoding='utf-8'))['zabbix_export']
    known = {}

    for group in root.get('template_groups', []):
        known['group|' + group['name']] = group['uuid']

    for template in root.get('templates', []):
        known['template|' + template['template']] = template['uuid']

        for item in template.get('items', []):
            known['item|' + item['key']] = item['uuid']

        for vmap in template.get('valuemaps', []):
            known['vmap|' + vmap['name']] = vmap['uuid']

        for dashboard in template.get('dashboards', []):
            known['dash|' + dashboard['name']] = dashboard['uuid']

        for rule in template.get('discovery_rules', []):
            known['lld|' + rule['key']] = rule['uuid']
            for proto in rule.get('item_prototypes', []):
                known['proto|' + proto['key']] = proto['uuid']
            for trigger in rule.get('trigger_prototypes', []):
                known['trigger|' + trigger['name']] = trigger['uuid']
            for graph in rule.get('graph_prototypes', []):
                known['gproto|' + graph['name']] = graph['uuid']

    for trigger in root.get('triggers', []):
        known['trigger|' + trigger['name']] = trigger['uuid']

    return known


def resolve_uuids(text, known):
    seen, created = set(), []

    for identity in SYMBOL.findall(text):
        if identity in seen:
            sys.exit('Duplicate identity: ' + identity)
        seen.add(identity)

        if identity not in known:
            known[identity] = uuid.uuid4().hex
            created.append(identity)

    for identity in sorted(seen, key=len, reverse=True):
        text = text.replace('@@' + identity + '@@', known[identity])

    unresolved = SYMBOL.findall(text)
    if unresolved:
        sys.exit('Unresolved identities: ' + str(unresolved))

    return text, len(seen) - len(created), created


def validate(text):
    """Cheap self-checks so a broken template never reaches the repository."""
    doc = yaml.safe_load(text)
    template = doc['zabbix_export']['templates'][0]
    host = template['template']

    uuids = re.findall(r'\b[0-9a-f]{32}\b', text)
    if len(uuids) != len(set(uuids)):
        sys.exit('Duplicate UUIDs in the generated template.')

    keys = {i['key'] for i in template['items']}
    for rule in template['discovery_rules']:
        keys |= {p['key'] for p in rule['item_prototypes']}

    reference = re.compile(r'/' + re.escape(host) + r'/([A-Za-z0-9_.]+(?:\[[^\[\]]*\])?)')
    triggers = list(doc['zabbix_export'].get('triggers', []))
    for rule in template['discovery_rules']:
        triggers += rule.get('trigger_prototypes', [])

    for trigger in triggers:
        for key in reference.findall(trigger['expression']):
            if key not in keys:
                sys.exit('Trigger "%s" references unknown key %s' % (trigger['name'], key))

    for dashboard in template.get('dashboards', []):
        for page in dashboard['pages']:
            for widget in page['widgets']:
                for field in widget.get('fields', []):
                    if field.get('type') == 'ITEM' and field['value']['key'] not in keys:
                        sys.exit('Dashboard references unknown key ' + field['value']['key'])

    return len(keys), len(triggers)


def main():
    text = io.open(SOURCE, encoding='utf-8').read()
    text = inline_sources(text)

    text, reused, created = resolve_uuids(text, index_published(OUTPUT))
    keys, triggers = validate(text)

    io.open(OUTPUT, 'w', encoding='utf-8', newline='\n').write(text)

    print('Built %s' % os.path.relpath(OUTPUT, ROOT))
    print('  UUIDs reused : %d' % reused)
    print('  UUIDs created: %d' % len(created))
    for identity in sorted(created):
        print('    + ' + identity)
    print('  item keys    : %d' % keys)
    print('  triggers     : %d' % triggers)


if __name__ == '__main__':
    main()
