pipeline {
  parameters {
    choice(
      name: 'ENV',
      choices: [
        'ci',
        'staging',
         'prod'
      ],
      description: 'Target environment (namespace: gxa-<env>). Requires charts/gxa/values-<env>.yaml.'
    )
    string(
      name: 'IMAGE_TAG',
      defaultValue: '',
      description: 'Container image tag to deploy (e.g. 37.6.64). Required.'
    )
    choice(
      name: 'RELEASE',
      choices: ['gxa'],
      description: 'Helm release / chart name.'
    )
    booleanParam(
      name: 'DRY_RUN',
      defaultValue: false,
      description: 'Helm dry-run only (no changes applied).'
    )
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '20'))
    disableConcurrentBuilds()
  }

  agent {
    kubernetes {
      cloud 'hh-webadmin-35'
      defaultContainer 'helm'
      yamlFile 'jenkins-k8s-pod-deploy.yaml'
    }
  }

  stages {
    stage('Validate parameters') {
      steps {
        script {
          if (!params.IMAGE_TAG?.trim()) {
            error('IMAGE_TAG is required (e.g. a version from atlas-web-bulk CI or "latest").')
          }
          def valuesFile = "charts/${params.RELEASE}/values-${params.ENV}.yaml"
          if (!fileExists(valuesFile)) {
            error("Missing ${valuesFile}. Add environment values before deploying to ${params.ENV}.")
          }
        }
      }
    }

    stage('Approve production deploy') {
      when { expression { params.ENV == 'prod' } }
      steps {
        input(
          message: "Deploy ${params.RELEASE} image tag ${params.IMAGE_TAG} to PRODUCTION?",
          ok: 'Deploy',
        )
      }
    }

    stage('Deploy with Helm') {
      steps {
        script {
          def secretsCredential = "gxa-secrets-${params.ENV}"
          withCredentials([
            file(credentialsId: secretsCredential, variable: 'SECRETS_SOURCE'),
          ]) {
            runHelmDeploy(params.RELEASE, params.ENV, params.IMAGE_TAG.trim(), params.DRY_RUN)
          }
        }
      }
    }

    // DevOps Portal persists deployment records on the controller; run off the K8s agent.
    stage('Record deployment') {
      when { expression { !params.DRY_RUN } }
      agent none
      steps {
        script {
          recordDeployment(params.RELEASE, params.ENV, params.IMAGE_TAG.trim())
        }
      }
    }
  }
}

def runHelmDeploy(String release, String env, String imageTag, boolean dryRun) {
  def namespace = "${release}-${env}"
  def valuesFile = "charts/${release}/values-${env}.yaml"
  def dryRunFlags = dryRun ? '--debug --dry-run' : ''

  echo "Deploying ${release} to ${namespace} with image tag ${imageTag}"

  sh """
    set -euo pipefail

    if [ ! -f "\${SECRETS_SOURCE}" ]; then
      echo "Missing secrets file from Jenkins credential gxa-secrets-${env}" >&2
      exit 1
    fi

    helm upgrade --install '${release}' 'charts/${release}' \\
      --namespace '${namespace}' \\
      --create-namespace \\
      -f '${valuesFile}' \\
      -f "\${SECRETS_SOURCE}" \\
      --set 'appVersion=${imageTag}' \\
      --set 'image.tag=${imageTag}' \\
      ${dryRunFlags}
  """

  if (!dryRun) {
    sh """
      set -euo pipefail
      kubectl rollout status deployment/${release} --namespace='${namespace}' --timeout=600s
    """
  }
}

def recordDeployment(String release, String targetEnv, String imageTag) {
  def namespace = "${release}-${targetEnv}"
  currentBuild.displayName = "#${env.BUILD_NUMBER} ${release}:${imageTag} → ${targetEnv}"
  currentBuild.description = "Deployed ${release} ${imageTag} to namespace ${namespace}"

  // targetService must match an environment label in Jenkins → DevOps Portal → Manage Environments
  def targetService = "${release}-${targetEnv}"

  reportDeployOperation(
    targetService: targetService,
    applicationName: release,
    applicationVersion: imageTag,
    tags: 'helm,k8s,fg-public',
  )
  echo "Recorded deployment of ${release} ${imageTag} to ${targetService} (DevOps Portal)"
}
