def envToAwsAccountMap = [
    dev: 'dev',
    stg: 'dev',
    qa: 'dev',
    prod: 'prod',
]

def setAWSCredentials(aws_account, access_key, secret_key, region) {
    AWS_DEFAULT_REGION = "${region}"
    if (access_key) {
        env.AWS_ACCESS_KEY_ID = access_key
        env.AWS_SECRET_ACCESS_KEY = secret_key
        
    } else {
        withCredentials([usernamePassword(credentialsId: "cloudsdk-ci-user-iqos-iot-${aws_account}", usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]){
            env.AWS_ACCESS_KEY_ID = "${AWS_ACCESS_KEY_ID}"
            env.AWS_SECRET_ACCESS_KEY = "${AWS_SECRET_ACCESS_KEY}"
        }
    }
}

pipeline {
    agent any
    parameters {
        gitParameter branchFilter: 'origin/(.*)', defaultValue: 'master', description: 'Git Branch', name: 'branch', quickFilterEnabled: true, sortMode: 'DESCENDING_SMART', type: 'PT_BRANCH'
        
		choice choices: ['dev', 'stg', 'qa', 'prod'], description: 'Environment', name: 'environment'
		

    }
    stages {
        stage('Checkout') {
            steps {
                container(name: 'custom', shell: 'bash') {
                    dir('.') {
                        checkout scm: [$class: 'GitSCM', branches: [[name: "${params.branch}"]], userRemoteConfigs: [[credentialsId: "iot_at_bitbucket.pmidce.com", url: "ssh://git@bitbucket.pmidce.com:2222/fuseapp/pmi-rrp-qa.git"]]]
                    }
                }
            }
        }
        stage('Init') {
            steps {
                container(name: 'custom', shell: 'bash') {
                     dir("infrastructure/terraform/environments/${params.environment}") {
                        script {
                            sh """
                                #!/bin/bash
                                echo 'Start initialization for environment ${params.environment}'
                            """
                            env.aws_account = envToAwsAccountMap[params.environment]
                            setAWSCredentials(env.aws_account, params.access_key, params.secret_key, params.region);
                            sh """
                                #!/bin/bash
                                terraform init -no-color
                            """
                        }
                    }
                }
            }
        }
        stage('Terraform plan') {
            steps {
                container(name: 'custom', shell: 'bash') {
                    dir("infrastructure/terraform/environments/${params.environment}") {
                        script {
                            sh """
                                #!/bin/bash
                                terraform plan -no-color
                            """
                        }
                    }
                }
            }
        }
        stage('Terraform apply') {
            input { 
                message "Please, check the terraform plan in the logs and press 'Yes' to proceed" 
                ok "Yes" 
            }
            steps {
                container(name: 'custom', shell: 'bash') {
                    dir("infrastructure/terraform/environments/${params.environment}") {
                        script {
                            sh """
                                #!/bin/bash
                                terraform apply -auto-approve -no-color
                            """
                        }
                    }
                }
            }
        }
    }
}
