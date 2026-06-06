import { Routes, Route } from "react-router-dom";
import Header from "./components/Header";

// Placeholder pages
const Home = () => <div className="text-white p-8">Home Page</div>;
const Lobby = () => <div className="text-white p-8">Game Lobby</div>;
const Stake = () => <div className="text-white p-8">Stake Mode</div>;
const Match = () => <div className="text-white p-8">Live Match</div>;
const MatchResult = () => <div className="text-white p-8">Match Result</div>;
const Spectate = () => <div className="text-white p-8">Spectate Lobby</div>;
const SpectateMatch = () => (
  <div className="text-white p-8">Live Spectator</div>
);
const Leaderboard = () => <div className="text-white p-8">Leaderboard</div>;
const Profile = () => <div className="text-white p-8">Player Profile</div>;

export default function App() {
  return (
    <div className="min-h-screen bg-black">
      <Header />
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/lobby" element={<Lobby />} />
        <Route path="/stake" element={<Stake />} />
        <Route path="/match/:id" element={<Match />} />
        <Route path="/match/:id/result" element={<MatchResult />} />
        <Route path="/spectate" element={<Spectate />} />
        <Route path="/spectate/:id" element={<SpectateMatch />} />
        <Route path="/leaderboard" element={<Leaderboard />} />
        <Route path="/profile/:address" element={<Profile />} />
      </Routes>
    </div>
  );
}
