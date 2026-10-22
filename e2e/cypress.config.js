const { defineConfig } = require('cypress');

module.exports = defineConfig({
  e2e: {
    baseUrl: process.env.CONSTROI_APP_URL || 'http://localhost:8090',
    supportFile: 'cypress/support/e2e.js',
    specPattern: 'cypress/e2e/**/*.cy.js',
    video: true,
    trashAssetsBeforeRuns: false,
    videosFolder: 'evidencias',
    screenshotsFolder: 'evidencias',
    defaultCommandTimeout: 20000,
    retries: { runMode: 0, openMode: 0 },
    viewportWidth: 1280,
    viewportHeight: 800,
    env: {
      apiUrl: process.env.CONSTROI_API_URL || 'http://localhost:8080',
    },
  },
});
