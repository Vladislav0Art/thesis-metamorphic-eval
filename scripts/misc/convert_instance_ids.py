from typing import List


# 47 resovable benchmarks:
# Here, "resovable" means that these benchmarks passed
# multi_swe_bench harness when executed on golden patches.
# (other benchmarks failed on golden patches; therefore they're
# excluded from the evaluation)
instance_ids = [
    "mockito/mockito:pr-3133",
    "mockito/mockito:pr-3167",
    "mockito/mockito:pr-3129",
    "mockito/mockito:pr-3173",
    "mockito/mockito:pr-3424",
    "mockito/mockito:pr-3220",
    "googlecontainertools/jib:pr-4144",
    "googlecontainertools/jib:pr-4035",
    "google/gson:pr-1555",
    "google/gson:pr-1391",
    "googlecontainertools/jib:pr-2542",
    "google/gson:pr-1093",
    "fasterxml/jackson-databind:pr-2036",
    "fasterxml/jackson-databind:pr-1923",
    "fasterxml/jackson-core:pr-1142",
    "fasterxml/jackson-core:pr-370",
    "fasterxml/jackson-core:pr-183",
    "fasterxml/jackson-core:pr-174",
    "elastic/logstash:pr-17021",
    "elastic/logstash:pr-17020",
    "elastic/logstash:pr-16579",
    "elastic/logstash:pr-16681",
    "elastic/logstash:pr-16094",
    "elastic/logstash:pr-15928",
    "elastic/logstash:pr-15697",
    "elastic/logstash:pr-14981",
    "elastic/logstash:pr-15000",
    "elastic/logstash:pr-14898",
    "elastic/logstash:pr-14970",
    "elastic/logstash:pr-14878",
    "elastic/logstash:pr-13997",
    "elastic/logstash:pr-14058",
    "elastic/logstash:pr-14897",
    "elastic/logstash:pr-14045",
    "elastic/logstash:pr-14000",
    "elastic/logstash:pr-14027",
    "elastic/logstash:pr-13825",
    "elastic/logstash:pr-13902",
    "elastic/logstash:pr-13930",
    "elastic/logstash:pr-13914",
    "elastic/logstash:pr-13931",
    "apache/dubbo:pr-10638",
    "apache/dubbo:pr-11781",
    "alibaba/fastjson2:pr-2097",
    "alibaba/fastjson2:pr-82",
    "alibaba/fastjson2:pr-2285",
    "alibaba/fastjson2:pr-1245",
]

def convert(instance_id: str) -> str:
    repo_part, pr_part = instance_id.split(":pr-")
    org, repo = repo_part.split("/")
    return f"{org}__{repo}-{pr_part}"


def main(instance_ids: List[str]):
    converted_list = []
    for id in instance_ids:
        converted_list.append(convert(id))
    print("Total number of benchmarks:", len(converted_list))
    print(",".join(converted_list))


if __name__ == "__main__":
    main(instance_ids)