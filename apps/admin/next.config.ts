import type { NextConfig } from 'next';
const config: NextConfig = { transpilePackages: ['@field-assist/contracts'], serverExternalPackages: ['@node-rs/argon2'], devIndicators: false };
export default config;

// OpenAI credentials stay in the server process environment, never in Next client env.
