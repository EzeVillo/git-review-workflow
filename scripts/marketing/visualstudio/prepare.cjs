// Disposable C# example for a real Visual Studio capture.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = process.argv[2];
if (!root || fs.existsSync(path.join(root, '.git'))) throw new Error('Pass a new example directory');
fs.mkdirSync(root, {recursive: true});
const write = (file, text) => { fs.mkdirSync(path.dirname(path.join(root, file)), {recursive: true}); fs.writeFileSync(path.join(root, file), text); };
const git = (...args) => cp.execFileSync('git', args, {cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']});
git('init', '-b', 'main'); git('config', 'user.name', 'Demo Reviewer'); git('config', 'user.email', 'demo@example.com');
git('config', 'core.autocrlf', 'false'); git('config', 'core.filemode', 'false'); git('config', 'reviewworkflow.base', 'main');
write('.gitignore', 'bin/\nobj/\n.vs/\n');
write('RateLimit.csproj', `<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework><IsTestProject>true</IsTestProject><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.11.1" />
    <PackageReference Include="xunit" Version="2.9.2" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />
  </ItemGroup>
</Project>\n`);
write('RateLimit.sln', `Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "RateLimit", "RateLimit.csproj", "{2E0DE0EA-ABCD-4BE0-8600-234BABBD2404}"
EndProject
Global
  GlobalSection(SolutionConfigurationPlatforms) = preSolution
    Debug|Any CPU = Debug|Any CPU
  EndGlobalSection
  GlobalSection(ProjectConfigurationPlatforms) = postSolution
    {2E0DE0EA-ABCD-4BE0-8600-234BABBD2404}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
    {2E0DE0EA-ABCD-4BE0-8600-234BABBD2404}.Debug|Any CPU.Build.0 = Debug|Any CPU
  EndGlobalSection
EndGlobal
`);
git('add', '.'); git('commit', '-m', 'Create login service'); git('switch', '-c', 'rate-limit');
write('src/Policy.cs', `namespace Login;

// The maximum number of attempts before blocking.
public static class Policy
{
    public const int MaxAttempts = 5;
}
`);
write('src/RateLimiter.cs', `namespace Login;

public static class RateLimiter
{
    // Block the next request once the limit is reached.
    public static bool IsAllowed(int attempts)
    {
        if (attempts > Policy.MaxAttempts)
        {
            return false;
        }

        return true;
    }
}
`);
write('tests/RateLimiterTests.cs', `using Xunit;
using Login;

public class RateLimiterTests
{
    [Fact]
    public void AllowsRequestsBelowTheLimit()
        => Assert.True(RateLimiter.IsAllowed(4));

    [Fact]
    public void BlocksRequestsAtTheLimit()
        => Assert.False(RateLimiter.IsAllowed(5));

    [Fact]
    public void BlocksRequestsAboveTheLimit()
        => Assert.False(RateLimiter.IsAllowed(6));
}
`);
git('add', '.'); git('commit', '-m', 'Add login rate limiting');
write('.review/walkthrough.md', `# Walkthrough

## Heads-up
Protect the login endpoint without locking out valid requests.

## 1. src/Policy.cs
The policy allows five attempts. Read this first: the boundary in the limiter must match it.

## 2. src/RateLimiter.cs
> key
Check the exact boundary: once five attempts are used, the next request must be blocked.

## 3. tests/RateLimiterTests.cs
Exercise the boundary. Run these tests before finishing the review.
`);
git('add', '.review'); git('commit', '-m', 'Explain the reading order');
console.log(root);
