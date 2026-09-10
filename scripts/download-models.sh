#!/bin/bash
# Download and verify the exact Kokoro model assets used by this local build.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESOURCES_DIR="${KOKORO_RESOURCES_DIR:-$PROJECT_DIR/Resources}"
MODEL_REPOSITORY="mlx-community/Kokoro-82M-bf16"
MODEL_REVISION="a71e4d38b236d968966a2002c4c895dbd12b1c3c"
BASE_URL="https://huggingface.co/${MODEL_REPOSITORY}/resolve/${MODEL_REVISION}"
ACTIVE_TEMP=""

cleanup() {
    if [ -n "$ACTIVE_TEMP" ] && [ -f "$ACTIVE_TEMP" ]; then
        rm -f "$ACTIVE_TEMP"
    fi
}
trap cleanup EXIT

sha256_file() {
    shasum -a 256 "$1" | awk '{print $1}'
}

file_size() {
    stat -f '%z' "$1"
}

verify_file() {
    local path="$1"
    local expected_size="$2"
    local expected_sha="$3"

    [ -f "$path" ] || return 1
    [ "$(file_size "$path")" = "$expected_size" ] || return 1
    [ "$(sha256_file "$path")" = "$expected_sha" ] || return 1
}

download_file() {
    local relative_path="$1"
    local expected_size="$2"
    local expected_sha="$3"
    local destination="$RESOURCES_DIR/$relative_path"

    mkdir -p "$(dirname "$destination")"

    if verify_file "$destination" "$expected_size" "$expected_sha"; then
        echo "  [verified] $relative_path"
        return 0
    fi

    if [ -e "$destination" ]; then
        echo "  [replace] $relative_path failed integrity verification"
        rm -f "$destination"
    else
        echo "  [download] $relative_path"
    fi

    ACTIVE_TEMP="$(mktemp "${destination}.tmp.XXXXXX")"
    curl \
        --fail \
        --location \
        --retry 3 \
        --retry-all-errors \
        --connect-timeout 20 \
        --progress-bar \
        --output "$ACTIVE_TEMP" \
        "$BASE_URL/$relative_path"

    if ! verify_file "$ACTIVE_TEMP" "$expected_size" "$expected_sha"; then
        echo "  [error] Integrity check failed for $relative_path" >&2
        exit 1
    fi

    mv "$ACTIVE_TEMP" "$destination"
    ACTIVE_TEMP=""
}

# Format: repository-relative path | exact byte size | SHA-256.
FILES=(
    "config.json|2351|5abb01e2403b072bf03d04fde160443e209d7a0dad49a423be15196b9b43c17f"
    "kokoro-v1_0.safetensors|327115152|4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8"
    "voices/af_alloy.safetensors|522320|5bb848d02ade7e37981809acad52a1761ef7a586ff9f30d02d65fd71c4af95f9"
    "voices/af_aoede.safetensors|522320|23809148777f2a2378983dd856bc14b9c261018279f916f98c23d86e844409a5"
    "voices/af_bella.safetensors|522320|112d310468cbb3cf23404d3d0b50ad3adf017b87bf38bf9edd15f4ad572df6a3"
    "voices/af_heart.safetensors|522320|2c1c733b0e6576c810e268d3e440c21dea4e0f0131a3ba4cfc98d7fe6136d094"
    "voices/af_jessica.safetensors|522320|c358448e4277b79e8b13b92033711660a1a2205c3940c2dfb16698b99fed58a8"
    "voices/af_kore.safetensors|522320|c491174280cb1ad25210a842f2f34b46a9ef904ec6f6a8e784839531795fa278"
    "voices/af_nicole.safetensors|522320|574656386022c81a029e9a72558191925f44c3de2dad2fa2e45751938557d062"
    "voices/af_nova.safetensors|522320|242b9a0a01eac1ac2865c69fc617a756b20d86df82d5fae3970533e2312ca50e"
    "voices/af_river.safetensors|522320|82c866b0b976d50e82cbd781ac7bc771471ce5bd21decf05ab92812a08fb1c04"
    "voices/af_sarah.safetensors|522320|4940072182542f54c1035d1daf4c1cf3136ca9baa9ac57c8e006b4befcc50be6"
    "voices/af_sky.safetensors|522320|957af332330db8e9bd7f9dc449475a946cb0d7d689afef64b91007bbbf20eaa0"
    "voices/am_adam.safetensors|522320|a4f60a3b9c20353c2604a17485ba53260502a758681a84d41e8af53cc559d929"
    "voices/am_echo.safetensors|522320|031fc608a900332c4e1a29bd0884f5d0e84bd0348261fa79981e5cbd138c950d"
    "voices/am_eric.safetensors|522320|1fb4a61dcee1f114f90886ecf29bc2feed05e29eed9caa6ddb109f1934d73274"
    "voices/am_fenrir.safetensors|522320|9abed964b906c4cae6f404d9849e76260689aea862bc6ca85fc3f5207ba96538"
    "voices/am_liam.safetensors|522320|66b65a96e16c3d91035a6e9019d9986ed524d27ce35b487270cdf61c99e3ebad"
    "voices/am_michael.safetensors|522320|3940147ded35deba0bb52e8132f89b719298e0520258c34584358aa5a24da2ea"
    "voices/am_onyx.safetensors|522320|b5d6132a5747648d98c82c9c4aaa9cf52d7230e63e403c1cb9c12858446ca5f5"
    "voices/am_puck.safetensors|522320|9a8c2e56413bd2063f814cb4c3885fc425876157369117c3f8258d03c8a9ad89"
    "voices/am_santa.safetensors|522320|d1f433b57ffccf105ea9e434ea19af6c2a8a7916ba6d1a73c34f0046bd226084"
    "voices/bf_alice.safetensors|522320|9c77e390d93d9db7c4a7526c3b1f393290a2be46f233b89a00b8188e850c20a8"
    "voices/bf_emma.safetensors|522320|8878a75a6661305849eeb1d6293a7177250193616e161b4c3100636434dfe69f"
    "voices/bf_isabella.safetensors|522320|f7b6076f025649699fcfed1a6debf13049a87afdc7aafc8c72b7d81246db6ead"
    "voices/bf_lily.safetensors|522320|ee77a419046a765420ac82cb46e8b8cf5754a0b9d20c340fece1d4b18be7ecdb"
    "voices/bm_daniel.safetensors|522320|b195dec592ee024f57ddc5bf481464596082ba60998a2a295eba90bfc1064f4b"
    "voices/bm_fable.safetensors|522320|9fa80184e96d016a744bc13b0b2e7695e55d6b855556fa003325cb1e5ebf2c2b"
    "voices/bm_george.safetensors|522320|a3d9b8995cbbe5536f954b6be2a0f1f312f077118ba0d4d2178fc41dc8306672"
    "voices/bm_lewis.safetensors|522320|e1e68013c21a141efe527aaec561e1174c2f5a6951b3bcecc8396adab315b247"
    "voices/ef_dora.safetensors|522320|13f6dfe8a498ce97a384186af045b586db6292869acbfde123a0fa2798229351"
    "voices/em_alex.safetensors|522320|e3bc4bf56ab47f0d52074cd3f84cd4f1713187285fdd85a545c6e167dfa3ab77"
    "voices/em_santa.safetensors|522320|37c44211b77b3f29512f420bd5a2e146c7769a5ad3d904b3455cccd55055db62"
    "voices/if_sara.safetensors|522320|2f3d092c8ba16f2007e8b234c9a55bdebec614a1e50143e41b39dd7f89fdb45b"
    "voices/im_nicola.safetensors|522320|96b62f7d25c3e7efce4f2506beeaa9f63bcc73524c7b2862738c65433fe9ba16"
    "voices/pf_dora.safetensors|522320|9a8d587d60d0e041f593f7e7488943e7a6821f0136961bf0e554572e12c91c77"
    "voices/pm_alex.safetensors|522320|bec864eaeb05cc1a6fa12777ad31faaae1b2ed6d5eb2a6f7370fb9cdc48e3e2f"
    "voices/pm_santa.safetensors|522320|5009747fd93841c0865830be0f577ed50800b41b2122c469dedf51bb8311f78d"
)

echo "Kokoro Voice verified model download"
echo "Repository: $MODEL_REPOSITORY"
echo "Revision:   $MODEL_REVISION"
echo "Target:     $RESOURCES_DIR"

for entry in "${FILES[@]}"; do
    IFS='|' read -r relative_path expected_size expected_sha <<< "$entry"
    download_file "$relative_path" "$expected_size" "$expected_sha"
done

voice_count="$(find "$RESOURCES_DIR/voices" -maxdepth 1 -type f -name '*.safetensors' | wc -l | tr -d ' ')"
if [ "$voice_count" != "36" ]; then
    echo "[error] Expected 36 verified voices, found $voice_count" >&2
    exit 1
fi

printf '%s\n' \
    "Kokoro model repository: $MODEL_REPOSITORY" \
    "Pinned revision: $MODEL_REVISION" \
    "Verified assets: model, config, and 36 voice embeddings" \
    > "$RESOURCES_DIR/MODEL_PROVENANCE.txt"

echo "All Kokoro assets are present and verified."
