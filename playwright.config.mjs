import {defineConfig} from '@playwright/test'
export default defineConfig({
  testDir:'tests/browser',
  timeout:180000,
  expect:{timeout:30000},
  workers:1,
  use:{viewport:{width:1280,height:800},headless:true,launchOptions:{executablePath:process.env.CHROMIUM_BIN || (process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined),args:['--use-angle=swiftshader','--enable-unsafe-swiftshader','--disable-background-timer-throttling','--disable-backgrounding-occluded-windows','--disable-renderer-backgrounding']},trace:'retain-on-failure'},
  webServer:{command:'npm run serve',url:'http://127.0.0.1:8080',reuseExistingServer:!process.env.CI,timeout:30000}
})
