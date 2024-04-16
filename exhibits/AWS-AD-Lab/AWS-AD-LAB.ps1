# To-do: prompt for the test user values - currently setting this in-line around line # 59

# Using the AWSPowerShell module
Import-Module AWSPowerShell

# Set the AWS region
Set-DefaultAWSRegion -Region us-east-1 -ProfileLocation default

# Create a new VPC - this will provision a default route table, network ACL, and security group
$NewVPCObj = New-EC2VPC -CidrBlock 192.168.1.0/24 -TagSpecification @{ResourceType="vpc";Tags=[Amazon.EC2.Model.Tag]@{Key="Name";Value="ActiveDirectoryLab"}}

# Get the default reoute table for the VPC
$NewRouteTableObj = Get-EC2RouteTable -Filter @{Name="vpc-id";Values=$NewVPCObj.VpcId}

# Create a new subnet for the VPC
$NewSubnetObj = New-EC2Subnet -VpcId $NewVPCObj.VpcId -CidrBlock 192.168.1.0/24
 
# Create a new Internet Gateway for the VPC
$NewInternetGatewayObj = New-EC2InternetGateway -Region us-east-1

# Attach the Internet Gateway to the VPC
Add-EC2InternetGateway -VpcId $NewVPCObj.VpcId -InternetGatewayId $NewInternetGatewayObj.InternetGatewayId

# Add the Internet Gateway to the VPC route table - Returns $True if successful
New-EC2Route -RouteTableId $NewRouteTableObj.RouteTableId -DestinationCidrBlock 0.0.0.0/0 `
-GatewayId $NewInternetGatewayObj.InternetGatewayId


# Create a new security group for the VPC
$NewSecurityGroupObj = New-EC2SecurityGroup -GroupName "PwshCreatedSecGroup" -Description "AD Lab Security Group" `
-VpcId $NewVPCObj.VpcId -Region us-east-1

# Find My Ip - to include in the new security group
$MyIp = Invoke-RestMethod -Uri "https://checkip.amazonaws.com/" -Method Get

# Create a new security group rule for the security group
$ip1 = new-object Amazon.EC2.Model.IpPermission
$ip1.IpProtocol = "tcp"
$ip1.FromPort = 0
$ip1.ToPort = 65535
$ip1.IpRanges = $MyIp.Trim() + "/32" # Need to trim the IP address returned from the API call to remove a line feed

# Add the security group rule to the security group - Returns $True if successful
Grant-EC2SecurityGroupIngress -GroupId $NewSecurityGroupObj -IpPermissions @( $ip1 )

# Compose a Keypair to access the EC2 instance - https://docs.aws.amazon.com/powershell/latest/userguide/pstools-ec2-keypairs.html
$testNewKeyPairObj = New-EC2KeyPair -KeyName "PwshCreatedKeyPair2"
$testNewKeyPairObj.KeyMaterial | Out-File -Encoding ascii .\access.pem

# Setup some inital run scripts
$script = '<powershell>
new-item -ItemType Directory -Name Temp -Path "c:\";
Start-Transcript -Path "C:\Temp\Transcript.txt";
Set-LocalUser -Name "Administrator" -Password (ConvertTo-SecureString -AsPlainText "AccessTestM3!" -Force);
New-LocalUser "admin" -Password (ConvertTo-SecureString -AsPlainText "AccessTestM3!" -Force);
Add-LocalGroupMember -Group "Administrators" -Member "admin";
$taskHash = @{`
    TaskName = "Shutdown-90";`
    Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-Command &{shutdown -t 5400 -s}";`
    Trigger = @((New-ScheduledTaskTrigger -Once -At ((Get-Date).AddHours(4))),(New-ScheduledTaskTrigger -AtStartup));`
    Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount`
    };Register-ScheduledTask @taskHash;
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools;
Import-Module ADDSDeployment;
$inputHash = @{CreateDnsDelegation=$false;
DatabasePath = "C:\Windows\NTDS";
DomainMode = "WinThreshold";
DomainName = "demoad.local";
DomainNetbiosName = "DEMOAD";
ForestMode = "WinThreshold";
InstallDns= $true;
LogPath = "C:\Windows\NTDS";
NoRebootOnCompletion = $false;
SysvolPath = "C:\Windows\SYSVOL";
Force=$true;
SafeModeAdministratorPassword=(ConvertTo-SecureString -AsPlainText "ReStoreEM3!" -Force)};
Install-ADDSForest @inputHash
Stop-Transcript;
</powershell>'
$UserData = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Script))

# Create a new EC2 instance in the VPC
#-InstanceType t2.micro `
$NewEC2InstanceObj = New-EC2Instance -ImageId ami-00d990e7e5ece7974 `
-KeyName "PwshCreatedKeyPair2" `
-AssociatePublicIp $true `
-SecurityGroupId $NewSecurityGroupObj `
-InstanceType t2.small `
-SubnetId $NewSubnetObj.SubnetId `
-TagSpecification @{ResourceType="instance";Tags=[Amazon.EC2.Model.Tag]@{Key="Name";Value="Gimme-a-DC-Num2"}} `
-InstanceInitiatedShutdownBehavior terminate `
-UserData $UserData

# Find the EC2 instance
$NewEC2InstanceIDData = Get-EC2Instance -Filter @{Name ="reservation-id"; Values = $NewEC2InstanceObj.ReservationId}

# Get the public IP address of the new EC2 instance
$NewEC2InstanceIDData.Instances[0].PublicIpAddress

# Get the admin password for the new EC2 instance
$NewEC2InstancePassword = Get-EC2PasswordData -InstanceId $NewEC2InstanceIDData.Instances[0].InstanceId -Decrypt -PemFile '.\access.pem'
Set-Clipboard -Value $NewEC2InstancePassword

mstsc.exe /v $NewEC2InstanceIDData.Instances[0].PublicIpAddress