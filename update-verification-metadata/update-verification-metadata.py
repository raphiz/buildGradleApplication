import sys
import xml.etree.ElementTree as ET

verification_file = sys.argv[1]
namespaces={'': "https://schema.gradle.org/dependency-verification"}
ET.register_namespace("", namespaces[''])

tree = ET.parse(verification_file)   

root = tree.getroot()
components = root.find('components', namespaces)
if (components):
    root.remove(components)

tree.write(verification_file, encoding='UTF-8', xml_declaration=True)

