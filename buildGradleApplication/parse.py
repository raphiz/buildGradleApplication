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
    module: object

@dataclass
class Module:
    name: str
    hash: object


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
            "module": {
                "name": artifact.module.name,
                "hash": toSri(artifact.module.hash.algo, artifact.module.hash.value),
                "hash_algo": artifact.module.hash.algo,
                "hash_value": artifact.module.hash.value,
            } if artifact.module is not None else None,
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

        component_artifacts = []
        for artifact_elem in component_elem.findall("default:artifact", namespaces):
            artifact_name = artifact_elem.get("name")
            hash_obj=None
            for algo in ["pgp", "md5", "sha1", "sha256", "sha512"]:
                elem = artifact_elem.find(f"default:{algo}", namespaces)
                if elem is not None:
                    value = elem.get("value")
                    hash_obj = Hash(algo=algo, value=value)

            artifact_obj = Artifact(name=artifact_name, hash=hash_obj, component=component_obj, module=None)
            component_artifacts.append(artifact_obj)

        # keep reference to Gradle module metadata if it exist
        module_name = f"{name}-{version}.module"
        module_artifact = next(
            (artifact for artifact in component_artifacts if artifact.name == module_name),
            None,
        )
        if module_artifact is not None:
            module = Module(name=module_artifact.name, hash=module_artifact.hash)
            for artifact in component_artifacts:
                if artifact is not module_artifact:
                    artifact.module = module

        artifacts.extend(component_artifacts)
    return artifacts


if __name__ == "__main__":
    main()