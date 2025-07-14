import sys
import os
import xml.etree.ElementTree as ET

main_file = sys.argv[1]
included_dirs = sys.argv[2:]

namespaces = {'': "https://schema.gradle.org/dependency-verification"}
ET.register_namespace("", namespaces[''])

def parse_components(path):
    if not os.path.isfile(path):
        return []
    tree = ET.parse(path)
    root = tree.getroot()
    components = root.find('components', namespaces)
    return components if components is not None else []


# Load main file
tree = ET.parse(main_file)
root = tree.getroot()
main_components = root.find('components', namespaces)
if main_components is None:
    main_components = ET.SubElement(root, 'components')

# Track seen component triples and artifact names
seen_components = {}
def component_key(c): return (c.get('group'), c.get('name'), c.get('version'))
def artifact_key(a): return a.get('name')

# Index existing components
for component in list(main_components):
    key = component_key(component)
    seen_components[key] = component

# Merge each included build's verification-metadata.xml
for build_dir in included_dirs:
    included_file = os.path.join(build_dir, main_file)
    included_components = parse_components(included_file)
    for component in included_components:
        key = component_key(component)
        if key in seen_components:
            existing = seen_components[key]
            existing_artifacts = {artifact_key(a): a for a in existing.findall('artifact', namespaces)}
            for artifact in component.findall('artifact', namespaces):
                a_key = artifact_key(artifact)
                if a_key not in existing_artifacts:
                    existing.append(artifact)
        else:
            seen_components[key] = component
            main_components.append(component)

# Write back merged result
tree.write(main_file, encoding='UTF-8', xml_declaration=True)
