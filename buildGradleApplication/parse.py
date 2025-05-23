import sys
import xml.etree.ElementTree as ET
import json
from dataclasses import dataclass
import base64

@dataclass
class Component:
    group: str
    name: str
    version: str

@dataclass
class Artifact:
    name: str
    hash: object
    component: object
    module_name: str
    module_hash: str

@dataclass
class Hash:
    algo: str
    value: str

def main():
    if len(sys.argv) <= 1:
        print("Missing verification.xml file")
        sys.exit(1)
    artifacts = parse(sys.argv[1])
    maven_repos = [repository.rstrip("/") for repository in sys.argv[2:]]

    outputs = []
    for artifact in artifacts:
        path = f"{artifact.component.group.replace('.', '/')}/{artifact.component.name}/{artifact.component.version}"
        output = {
            "url_prefixes": [f"{maven_repo}/{path}" for maven_repo in maven_repos],
            "path": path,
            "name": artifact.name,
            "module_name": artifact.module_name,
            "module_hash": artifact.module_hash,
            "component": {
                "group": artifact.component.group,
                "name": artifact.component.name,
                "version": artifact.component.version,
            },
            "hash": toSri(artifact.hash.algo, artifact.hash.value),
            "hash_algo": artifact.hash.algo,
            "hash_value": artifact.hash.value,
        }
        outputs.append(output)
    print(json.dumps(outputs))

def toSri(algo, hash):
    hash_bytes = bytes.fromhex(hash)
    encoded_hash = base64.b64encode(hash_bytes)
    decoded_hash = encoded_hash.decode()
    return f"{algo}-{decoded_hash}"


def parse(xml_file):
    namespaces = {
        "default": "https://schema.gradle.org/dependency-verification"
    }

    root = ET.parse(xml_file).getroot()
    artifacts = []

    for component_elem in root.findall(".//default:component", namespaces):
        group = component_elem.get("group")
        name = component_elem.get("name")
        version = component_elem.get("version")
        component_obj = Component(group=group, name=name, version=version)
        module_name = None
        module_hash = None

        for artifact_elem in component_elem.findall("default:artifact", namespaces):
            artifact_name = artifact_elem.get("name")
            hash_obj=None
            for algo in ["pgp", "md5", "sha1", "sha256", "sha512"]:
                elem = artifact_elem.find(f"default:{algo}", namespaces)
                if elem is not None:
                    value = elem.get("value")
                    hash_obj = Hash(algo=algo, value=value)

            artifact_obj = Artifact(name=artifact_name, hash=hash_obj, component=component_obj, module_name=module_name, module_hash=module_hash)
            artifacts.append(artifact_obj)

            if artifact_name.endswith(".module"):
                module_name = artifact_name
                module_hash = toSri(hash_obj.algo, hash_obj.value)

    return artifacts


if __name__ == "__main__":
    main()