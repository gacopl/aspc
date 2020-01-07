# aspc - AWS Switch Profile with Credentials
Switcher that handles IdP like OKTA the right way, no wrapper scripts, no expired tokens in middle of your important work. 

Switch profile and use your good ol' aws cli like you and your apps are used to. It is faster than any wrapper script that will always have to get at least new STS token for **each** command you issue, you save at least 1s with every aws command issued

Also helps with chained roles restrictions, and provides AWS access to commands that do not understand IdP or cred_process yet (terraform s3 backend was culprit that started this idea), and **autorefreshes** those 1h hard limit chained roles sts tokens you don't like (normal tokens as well)

Tested with bash on Ubuntu and aws-okta, it's far from state of the art but gets the job done well.

Should work with other Identity Providers as long as they support cred_process and you put them in aws config, for autorefresher support IdP should have ability to export creds and expiration info to ~/.aws/credentials

# Overview
This repo provides bash functions that will streamline usage of AWS profiles, allows to use Chained accounts and roles, autorefreshes tokens to avoid 1h limit on chained roles. etc. You are able to switch profiles and credentials easily and if you add it to PS1 you will know which profile is currently used, when tokens expire or maybe that they are autorefreshing etc. It helps 

* asp [profile-name] - standard profile switcher it will use creds in following order: env, credentials file, and credential_process. The most optimum is when your main account has credential_process setup to use aws-okta and other accounts with defined roles (cross-account or not) use the main account as source profile. In such scenario no creds are stored in env or credentials files, and aws-okta takes care of caching those (at least SAML session for okta)

* aspe [profile-name] - this will switch profile and inject credentials into current shell env for those apps that do not understand credential_process yet. Such credentials when roles are chained are not valid longer than 1h, but you will get a nice indicator when they expire so no more surprises in middle of your important deploy!

* aspc [profile-name | autooff | autoon] - this one will get credentials for any account through credential_process and put it in ~/.aws/credentials it will also start system global autorefresher and will keep refreshing that token until you exit your current shell or change profile. It is multi session aware, so you can have multiple shells running with same profile, and until any of them is still running your creds for that profile will be refreshed before they expire. You will also get indicators if your current session is hooked to autorefresher or maybe not but another shell is refreshing token. And you can turn off and on global autorefresher

* __asp_expiry - this function provides current profile and status indicators on token expiration and autorefresher status it is perfectly suitable to put it in PS1 or POWERLINE shell or any place you see fit. 

[profile-name] - if not provided current profile will be used to get env (aspe) or credentials file (aspc) credentials. 

It is common practice to specify profile names as account_name.role_name in organizations where multiple roles are present in each account. Everytime you use for example asp login.devops, devops will be set as your "AWS_DEFAULT_ROLE" if then for example you issue asp shared, you'll be switched to shared.devops profile

## Quick workflow overview
```
asp login.devops -> login.devops profile

asp shared -> shared.devops profile

asp shared.admin -> shared.admin profile

asp login -> login.admin profile

aspc -> login.admin profile will be selected with credentials setup and autorefresher session will be started

asp -> login.admin profile will be selected and autorefresher session will be closed

aspe -> login.admin profile will be selected and creds will injected to your current env
```

As a bonus `<TAB>` autocompletion works out-of-the-box

# Installation

## Prerequisites
To use credentials autorefresher You will need patched aws-okta build until they accept my PR.

```bash
apt-get install build-essentials libusb-1.0-0-dev
sudo snap install --classic go ## or any other way for go 1.13 installation
git clone -b write-to-credentials-expiration-info git@github.com:gacopl/aws-okta.git
cd aws-okta
make dist/aws-okta-`git describe --tags`-linux-amd64
cp dist/aws-okta* ~/bin/
```

Proper AWS Profiles, main account should be configured for credential process and other accounts roles should be configured with source_profile pointing to main account, also role_session_name should be set if your org expects and validates them

~/.aws/credentials example
```
[login.devops]
credential_process = aws-okta cred-process login.devops --mfa-factor-type push --mfa-provider OKTA
```

~/.aws/config example
```
[profile login.cloudops]
s3 =
    signature_version = s3v4
output          = json
session_ttl = 4h ## UPTO 12H if your default SAML role allows it
aws_saml_url = home/amazon_aws/aslikdj54489059o4askmd/4899 ## OKTA APP SAML URL
role_session_name = user@domain.com ## ROLE SESSION NAME example

[profile shared.devops]
s3 =
    signature_version = s3v4
output         = json
source_profile = login.devops ## POINT TO YOUR MAIN ACCOUNT/PROFILE
role_arn       = arn:aws:iam::XXXXXXX:role/devops/DevOps ## ROLE ARN TO ASSUME 
role_session_name = user@domain.com ## ROLE SESSION NAME example

assume_role_ttl = 1h ## WHEN CHAINED THIS SHOULD ALWAYS BE 1H - AWS HARD LIMIT
region = eu-central-1
```

## Installation of aspc functions

```bash
git clone git@github.com:gacopl/aws-okta.git
cp aspc/aspc.sh ~/bin/aspc.sh
chmod a+x ~/bin/aspc.sh
```

Put following in your ~/.bashrc or ~/.bash_aliases or ~/.profile (depends on distro):
```bash
source ~/bin/aspc.sh

PS1+="$(__asp_expiry)" ## this will get you going with asp status in your shell prompt, but i advise to find original PS1 (~/.bashrc in Ubuntu) and put it exactly where you like or tune it even more ;)

asp login.devops ## this will start any shell already switched to login.devops profile and set your AWS_DEFAULT_ROLE to devops
```

## Additional configuration
You can add those variables in same file you sourced aspc.sh script to tune behaviour, these should be self explanatory
```bash
AWS_DEFAULT_ROLE=devops ## if you put role names after dot you will be able to pass only account name ie aspc login will switch to login.devops profile in that case instead of full profile name this will be your default in every new shell
ASPC_AUTOREFRESHER_ENABLED=true
ASPC_AUTOREFRESHER_RUN_EVERY=180
ASPC_REFRESH_THRESHOLD=10
ASPC_OKTA_MFA_SETTINGS="--mfa-factor-type push --mfa-provider OKTA" ## or "--mfa-factor-type token:software:totp --mfa-profider GOOGLE" for GOOGLE AUTHENTICATOR
ASPC_SESSION_FILE_PREFIX=/tmp/aspc-autorefresher ## this prefereably should be on tmpfs filesystem defaults will work on Ubuntu
ASPC_AUTOREFRESHER_LOCK=/run/lock/aspc_autorefresher_${USER} ## this prefereably should be on tmpfs filesystem defaults will work on Ubuntu (Leave USER variable as is!!)
```

# Notes on security
Some may say that using ~/.aws/credentials file is less secure than using okta wrapper script, but if your tokens expire within 1hr anyway due to chained role limit it shouldnt be a problem. 
**Especially** if one can relatively easily get those creds from okta-wrapper script session anyway by reaching to shell env of that wrapper. 

I will come with update for autorefresher that will delete tokens from credentials file when there are no active sessions to make it more secure 

# TODO
* screenshots and better readme
* cleanup of old tokens
* other IDP support
* Mac/different shells support (for colors mainly - otherwise it should work)