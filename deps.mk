# ./lib/Amazon/Lambda/Runtime/Builder.pm.in
./lib/Amazon/Lambda/Runtime/Builder.pm: \
    ./lib/Amazon/Lambda/Runtime/Builder/Role/CheckDeps.pm \
    ./lib/Amazon/Lambda/Runtime/Builder/Role/Config.pm \
    ./lib/Amazon/Lambda/Runtime/Builder/Role/Install.pm

# ./lib/Amazon/Lambda/Runtime/Builder/Helper.pm.in
./lib/Amazon/Lambda/Runtime/Builder/Helper.pm: \
    ./lib/Amazon/Lambda/Runtime/Builder/Role/CloudFront.pm \
    ./lib/Amazon/Lambda/Runtime/Builder/Role/ECR.pm \
    ./lib/Amazon/Lambda/Runtime/Builder/Role/ELBv2.pm \
    ./lib/Amazon/Lambda/Runtime/Builder/Role/Events.pm \
    ./lib/Amazon/Lambda/Runtime/Builder/Role/IAM.pm \
    ./lib/Amazon/Lambda/Runtime/Builder/Role/Lambda.pm \
    ./lib/Amazon/Lambda/Runtime/Builder/Role/Logs.pm \
    ./lib/Amazon/Lambda/Runtime/Builder/Role/S3.pm \
    ./lib/Amazon/Lambda/Runtime/Builder/Role/SNS.pm \
    ./lib/Amazon/Lambda/Runtime/Builder/Role/SQS.pm \
    ./lib/Amazon/Lambda/Runtime/Builder/Role/STS.pm

# ./lib/Amazon/Lambda/Runtime/Builder/Role/Install.pm.in
./lib/Amazon/Lambda/Runtime/Builder/Role/Install.pm: \
    ./lib/Amazon/Lambda/Runtime/Builder/Policies.pm

