#!/bin/bash
# TODO: Delete after composite CI is release or PR is ready for review in case it was committed by mistake

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <AWS_ACCOUNT_ID> <ECR_REPOSITORY_NAME> <REPOSITORY_NAME>"
    exit 1
fi

check-repository-name () {
    REGEX="^(usdn|smardex|alt|cross-project|vordex)-[[:alnum:]]+$"

    if [[ ! "$1" =~ $REGEX ]]; then
        echo "$1 must match $REGEX"
        echo "Aborting..."
        exit 1
    fi
}

ECR_REGISTRY="$1.dkr.ecr.eu-central-1.amazonaws.com"
AWS_REPOSITORY_NAME="$2"
REPOSITORY_NAME="$3"

check-repository-name $REPOSITORY_NAME

VERSION=$(cat "package.json" | jq -r '.version')
IMAGE_NAME="$(echo $REPOSITORY_NAME | sed -rn 's/^(usdn|smardex|alt|cross-project|vordex)-[[:alnum:]]+$/\1/p')-anvil-contracts"
IMAGE_TAG="$(echo -n "$IMAGE_NAME" | sed 's/@//g')-${VERSION}"

# Checking if the Docker image already exists in the ECR
IMAGE_META=$(aws ecr describe-images --repository-name="$AWS_REPOSITORY_NAME" --image-ids=imageTag="${IMAGE_TAG}" 2> /dev/null)

if [[ ! $? == 0 ]]; then
    echo "Building Docker image $IMAGE_NAME"
    docker build -t "$IMAGE_NAME" . --no-cache
    docker tag "$IMAGE_NAME:latest" "$ECR_REGISTRY/$AWS_REPOSITORY_NAME:$IMAGE_TAG"

    # Create ECR repository if it doesn't exist
    aws ecr describe-repositories --repository-names ${AWS_REPOSITORY_NAME} || aws ecr create-repository --repository-name ${AWS_REPOSITORY_NAME}

    echo "Publishing"
    docker push "$ECR_REGISTRY/$AWS_REPOSITORY_NAME:$IMAGE_TAG"
else
    echo "$IMAGE_TAG already exists in $AWS_REPOSITORY_NAME"
fi

