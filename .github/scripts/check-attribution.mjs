import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

// Reject attribution trailers, while allowing ordinary mentions in prose.
const forbiddenTrailer = /^co-authored-by:[^\r\n]*(?:\bclaude\b|<noreply@anthropic\.com>)/im;
const shaPattern = /^[a-f0-9]{40}$/i;

function git(...args) {
  return execFileSync('git', args, { encoding: 'utf8' }).trim();
}

function check() {
  const [base, head] = process.argv.slice(2);
  if (!shaPattern.test(base ?? '') || !shaPattern.test(head ?? '')) {
    throw new Error('Informe os SHAs completos da base e do head.');
  }

  const commits = git('rev-list', `${base}..${head}`).split('\n').filter(Boolean);
  const rejected = commits.filter((sha) =>
    forbiddenTrailer.test(git('show', '-s', '--format=%B', sha)),
  );
  if (rejected.length) {
    throw new Error(`Coautoria do Claude encontrada nos commits: ${rejected.join(', ')}.`);
  }

  if (process.env.GITHUB_EVENT_PATH) {
    const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
    const pr = event.pull_request;
    if (pr && forbiddenTrailer.test(`${pr.title ?? ''}\n${pr.body ?? ''}`)) {
      throw new Error('Remova a coautoria do Claude do titulo/corpo do PR antes do merge.');
    }
  }
  console.log(`Politica de coautoria aprovada para ${commits.length} commit(s).`);
}

try {
  check();
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
