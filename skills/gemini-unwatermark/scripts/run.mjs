import { spawn, spawnSync } from 'node:child_process';
import { delimiter } from 'node:path';

const PACKAGE_SPEC = process.env.GWR_SKILL_CLI_SPEC || '@pilio/gemini-watermark-remover';
const CLI_BIN = 'gwr';

function hasOnPath(cmd) {
  return spawnSync('which', [cmd], { stdio: 'ignore' }).status === 0;
}

function npmGlobalBin() {
  const result = spawnSync('npm', ['bin', '-g'], { encoding: 'utf8' });
  if (result.status === 0 && result.stdout) {
    return result.stdout.trim();
  }
  const prefix = spawnSync('npm', ['config', 'get', 'prefix'], { encoding: 'utf8' });
  if (prefix.status === 0 && prefix.stdout) {
    return `${prefix.stdout.trim()}/bin`;
  }
  return null;
}

function ensureInstalled() {
  if (hasOnPath(CLI_BIN)) return;

  if (!hasOnPath('npm')) {
    process.stderr.write(`npm is required to install ${PACKAGE_SPEC} but was not found on PATH.\n`);
    process.exit(1);
  }

  process.stderr.write(`Installing ${PACKAGE_SPEC} globally (first-run setup)...\n`);
  const install = spawnSync('npm', ['install', '-g', PACKAGE_SPEC], { stdio: 'inherit' });
  if (install.status !== 0) {
    process.stderr.write(`Failed to install ${PACKAGE_SPEC}.\n`);
    process.exit(install.status ?? 1);
  }

  if (hasOnPath(CLI_BIN)) return;

  const bin = npmGlobalBin();
  const pathSegments = (process.env.PATH || '').split(delimiter);
  if (bin && !pathSegments.includes(bin)) {
    process.stderr.write(
      `Installed ${PACKAGE_SPEC} but '${CLI_BIN}' is not on PATH.\n` +
      `Add the npm global bin to PATH and retry:\n  export PATH="${bin}:$PATH"\n`
    );
  } else {
    process.stderr.write(`Installed ${PACKAGE_SPEC} but '${CLI_BIN}' is still not callable.\n`);
  }
  process.exit(1);
}

function runCli(args) {
  return new Promise((resolve, reject) => {
    const child = spawn(CLI_BIN, args, { stdio: 'inherit' });
    child.on('error', reject);
    child.on('close', (code) => resolve(code ?? 1));
  });
}

ensureInstalled();
runCli(process.argv.slice(2))
  .then((code) => { process.exitCode = code; })
  .catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
