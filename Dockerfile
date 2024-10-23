# Base image with Node.js
FROM node:18-alpine AS base

# Install dependencies only when needed
FROM base AS deps
WORKDIR /app

# Установка libc6-compat для специфического окружения node-alpine
RUN apk add --no-cache libc6-compat

# Копируем lock файлы для управления зависимостями
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./

# Установка зависимостей на основе наличия lock файла
RUN \
  if [ -f yarn.lock ]; then yarn --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm i --frozen-lockfile; \
  else echo "Lockfile not found." && exit 1; fi


# Stage для сборки приложения
FROM base AS builder
WORKDIR /app
# Копируем только нужные файлы, установленные в предыдущем слое
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Смотрите https://nextjs.org/telemetry для подробностей о телеметрии
# ENV NEXT_TELEMETRY_DISABLED=1

# Сборка проекта
RUN \
  if [ -f yarn.lock ]; then yarn run build; \
  elif [ -f package-lock.json ]; then npm run build; \
  elif [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm run build; \
  else echo "Lockfile not found." && exit 1; fi

# Stage для выполнения готового проекта
FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production
# ENV NEXT_TELEMETRY_DISABLED=1

# Добавление системных пользователей
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# Копирование статических и standalone файлов из builder
COPY --from=builder /app/public ./public
RUN mkdir .next && chown nextjs:nodejs .next
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

# Открытие порта
EXPOSE 3000

ENV PORT=3000

# Выполнение серверного скрипта
ENV HOSTNAME="0.0.0.0"
CMD ["node", "server.js"]