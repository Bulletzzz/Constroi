import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const script = fileURLToPath(new URL('./check-attribution.mjs', import.meta.url));
const temporaryRoot = realpathSync(tmpdir());

function repository(t) {
  const cwd = mkdtempSync(join(temporaryRoot, 'constroi-attribution-'));
  t.after(() => {
    const target = resolve(cwd);
    assert.ok(target.startsWith(`${temporaryRoot}${sep}constroi-attribution-`));
    rmSync(target, { recursive: true, force: true });
  });
  const git = (...args) => execFileSync('git', args, { cwd, encoding: 'utf8' }).trim();
  git('init', '--quiet');
  git('config', 'user.name', 'Teste');
  git('config', 'user.email', 'test@example.com');
  git('config', 'commit.gpgsign', 'false');
  const commit = (message) => {
    git('commit', '--quiet', '--allow-empty', '-m', message);
    return git('rev-parse', 'HEAD');
  };
  const base = commit('Base');
  const run = (head, event, start = base) => {
    const env = { ...process.env };
    delete env.GITHUB_EVENT_PATH;
    if (event) {
      env.GITHUB_EVENT_PATH = join(cwd, 'event.json');
      writeFileSync(env.GITHUB_EVENT_PATH, JSON.stringify(event));
    }
    return spawnSync(process.execPath, [script, start, head], { cwd, env, encoding: 'utf8' });
  };
  return { commit, run };
}

test('aceita mencoes em prosa e coautores humanos', (t) => {
  const { commit, run } = repository(t);
  const head = commit('Documenta Claude\n\nCo-Authored-By: Maria <maria@example.com>');
  assert.equal(run(head).status, 0);
});

test('bloqueia o trailer usado pelo Claude', (t) => {
  const { commit, run } = repository(t);
  const head = commit('Feature\n\nCo-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>');
  const result = run(head);
  assert.equal(result.status, 1);
  assert.ok(result.stderr.includes(head));
});

test('bloqueia Claude com outro email e o email conhecido com outro nome', (t) => {
  const { commit, run } = repository(t);
  assert.equal(run(commit('Feature\n\nco-authored-by: CLAUDE <other@example.com>')).status, 1);
  const base = commit('Nova base');
  const head = commit('Feature\n\nCO-AUTHORED-BY: Assistente <NOREPLY@ANTHROPIC.COM>');
  assert.equal(run(head, undefined, base).status, 1);
});

test('analisa todos os commits novos e nao somente o ultimo', (t) => {
  const { commit, run } = repository(t);
  commit('Feature\n\nCo-Authored-By: Claude <other@example.com>');
  assert.equal(run(commit('Correcao posterior')).status, 1);
});

test('nao bloqueia por commits antigos que ja estao na base', (t) => {
  const { commit, run } = repository(t);
  const base = commit('Historico\n\nCo-Authored-By: Claude <other@example.com>');
  assert.equal(run(commit('Feature humana'), undefined, base).status, 0);
});

test('bloqueia trailer no corpo do PR que pode entrar na mensagem de merge', (t) => {
  const { commit, run } = repository(t);
  const head = commit('Feature humana');
  const event = { pull_request: { title: 'Feature', body: 'Co-Authored-By: Claude <other@example.com>' } };
  assert.equal(run(head, event).status, 1);
  event.pull_request.body = 'Atualiza a documentacao sobre Claude.';
  assert.equal(run(head, event).status, 0);
});

test('recusa argumentos que nao sejam SHAs completos', (t) => {
  const { commit, run } = repository(t);
  assert.equal(run(commit('Feature'), undefined, '--all').status, 1);
});
