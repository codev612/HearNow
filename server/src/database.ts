import { MongoClient, Db, Collection, ObjectId } from 'mongodb';
import crypto from 'crypto';

// User type definition
export interface User {
  _id?: ObjectId;
  id?: string; // For backward compatibility, will be _id.toString()
  email: string;
  password_hash: string;
  email_verified: boolean;
  verification_token: string | null;
  verification_token_expires: number | null;
  reset_token: string | null;
  reset_token_expires: number | null;
  created_at: number;
  updated_at: number;
}

export interface PublicUser {
  id: string;
  email: string;
  email_verified: boolean;
  created_at: number;
}

export interface CreateUserResult {
  id: string;
  email: string;
  verification_token: string;
}

// MongoDB connection - read from env at runtime
const getMongoUri = (): string => {
  const uri = process.env.MONGODB_URI?.trim();
  if (!uri) {
    console.warn('WARNING: MONGODB_URI environment variable not set! Using default: mongodb://localhost:27017');
    console.warn('Make sure MONGODB_URI is set in your .env file in the project root or server directory');
    return 'mongodb://localhost:27017';
  }
  // Hide credentials in log but show that URI was loaded
  const safeUri = uri.replace(/(mongodb:\/\/[^:]+:)([^@]+)@/, '$1***@');
  console.log(`MongoDB URI loaded from environment (${safeUri})`);
  return uri;
};

const getDbName = (): string => {
  return process.env.MONGODB_DB_NAME || 'hearnow';
};

let client: MongoClient | null = null;
let db: Db | null = null;
let usersCollection: Collection<User> | null = null;

// Initialize MongoDB connection
export const connectDB = async (): Promise<void> => {
  try {
    if (!client) {
      const mongoUri = getMongoUri();
      const dbName = getDbName();
      client = new MongoClient(mongoUri);
      await client.connect();
      console.log(`Connected to MongoDB (database: ${dbName})`);
    }
    
    if (!db) {
      db = client.db(getDbName());
    }
    
    if (!usersCollection) {
      usersCollection = db.collection<User>('users');
      
      // Create indexes
      await usersCollection.createIndex({ email: 1 }, { unique: true });
      await usersCollection.createIndex({ verification_token: 1 });
      await usersCollection.createIndex({ reset_token: 1 });
      await usersCollection.createIndex({ 'verification_token_expires': 1 });
      await usersCollection.createIndex({ 'reset_token_expires': 1 });
    }
  } catch (error) {
    console.error('MongoDB connection error:', error);
    throw error;
  }
};

// Get users collection (ensure connection is established)
const getUsersCollection = (): Collection<User> => {
  if (!usersCollection) {
    throw new Error('Database not connected. Call connectDB() first.');
  }
  return usersCollection;
};

// Helper function to convert MongoDB user to API format
const toUser = (doc: User | null): User | undefined => {
  if (!doc) return undefined;
  return {
    ...doc,
    id: doc._id?.toString(),
  };
};

// Helper function to convert to PublicUser
const toPublicUser = (doc: User | null): PublicUser | undefined => {
  if (!doc) return undefined;
  return {
    id: doc._id?.toString() || '',
    email: doc.email,
    email_verified: doc.email_verified,
    created_at: doc.created_at,
  };
};

// Helper functions
export const generateToken = (): string => {
  return crypto.randomBytes(32).toString('hex');
};

export const setVerificationToken = async (userId: string, token: string, expiresInHours: number = 24): Promise<void> => {
  const expiresAt = Date.now() + expiresInHours * 60 * 60 * 1000;
  const collection = getUsersCollection();
  await collection.updateOne(
    { _id: new ObjectId(userId) },
    {
      $set: {
        verification_token: token,
        verification_token_expires: expiresAt,
        updated_at: Date.now(),
      },
    }
  );
};

export const setResetToken = async (userId: string, token: string, expiresInHours: number = 1): Promise<void> => {
  const expiresAt = Date.now() + expiresInHours * 60 * 60 * 1000;
  const collection = getUsersCollection();
  await collection.updateOne(
    { _id: new ObjectId(userId) },
    {
      $set: {
        reset_token: token,
        reset_token_expires: expiresAt,
        updated_at: Date.now(),
      },
    }
  );
};

export const clearVerificationToken = async (userId: string): Promise<void> => {
  const collection = getUsersCollection();
  await collection.updateOne(
    { _id: new ObjectId(userId) },
    {
      $set: {
        verification_token: null,
        verification_token_expires: null,
        updated_at: Date.now(),
      },
    }
  );
};

export const clearResetToken = async (userId: string): Promise<void> => {
  const collection = getUsersCollection();
  await collection.updateOne(
    { _id: new ObjectId(userId) },
    {
      $set: {
        reset_token: null,
        reset_token_expires: null,
        updated_at: Date.now(),
      },
    }
  );
};

export const markEmailVerified = async (userId: string): Promise<void> => {
  const collection = getUsersCollection();
  await collection.updateOne(
    { _id: new ObjectId(userId) },
    {
      $set: {
        email_verified: true,
        verification_token: null,
        verification_token_expires: null,
        updated_at: Date.now(),
      },
    }
  );
};

// User operations
export const createUser = async (email: string, passwordHash: string): Promise<CreateUserResult> => {
  const token = generateToken();
  const expiresAt = Date.now() + 24 * 60 * 60 * 1000; // 24 hours
  const now = Date.now();

  const userDoc: Omit<User, '_id' | 'id'> = {
    email,
    password_hash: passwordHash,
    email_verified: false,
    verification_token: token,
    verification_token_expires: expiresAt,
    reset_token: null,
    reset_token_expires: null,
    created_at: now,
    updated_at: now,
  };

  const collection = getUsersCollection();
  const result = await collection.insertOne(userDoc as Omit<User, '_id'>);

  return {
    id: result.insertedId.toString(),
    email,
    verification_token: token,
  };
};

export const getUserByEmail = async (email: string): Promise<User | undefined> => {
  const collection = getUsersCollection();
  const user = await collection.findOne({ email });
  return toUser(user);
};

export const getUserById = async (id: string): Promise<PublicUser | undefined> => {
  const collection = getUsersCollection();
  const user = await collection.findOne({ _id: new ObjectId(id) });
  return toPublicUser(user);
};

export const getUserByVerificationToken = async (token: string): Promise<User | undefined> => {
  const collection = getUsersCollection();
  const user = await collection.findOne({
    verification_token: token,
    verification_token_expires: { $gt: Date.now() },
  });
  return toUser(user);
};

export const getUserByResetToken = async (token: string): Promise<User | undefined> => {
  const collection = getUsersCollection();
  const user = await collection.findOne({
    reset_token: token,
    reset_token_expires: { $gt: Date.now() },
  });
  return toUser(user);
};

export const updatePassword = async (userId: string, passwordHash: string): Promise<void> => {
  const collection = getUsersCollection();
  await collection.updateOne(
    { _id: new ObjectId(userId) },
    {
      $set: {
        password_hash: passwordHash,
        reset_token: null,
        reset_token_expires: null,
        updated_at: Date.now(),
      },
    }
  );
};

// Close database connection
export const closeDB = async (): Promise<void> => {
  if (client) {
    await client.close();
    client = null;
    db = null;
    usersCollection = null;
    console.log('MongoDB connection closed');
  }
};

export default { connectDB, closeDB, getUsersCollection };
