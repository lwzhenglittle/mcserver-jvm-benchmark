package bench;

import com.destroystokyo.paper.event.server.ServerTickEndEvent;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.plugin.java.JavaPlugin;

import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.ConcurrentLinkedQueue;

/**
 * TickLogger — per-tick MSPT recorder (P6).
 * Writes CSV: tick,epoch_ms,duration_ms,time_remaining_ns
 * Output path: -Dticklogger.out=<path> (default: plugins/TickLogger/mspt.csv)
 * Tick thread only does queue.offer; a daemon writer thread does I/O.
 */
public class TickLogger extends JavaPlugin implements Listener {

    private final ConcurrentLinkedQueue<String> queue = new ConcurrentLinkedQueue<>();
    private volatile boolean running;
    private Thread writer;

    @Override
    public void onEnable() {
        String out = System.getProperty("ticklogger.out",
                getDataFolder().toPath().resolve("mspt.csv").toString());
        Path path = Path.of(out);
        try {
            Files.createDirectories(path.getParent());
            BufferedWriter bw = Files.newBufferedWriter(path);
            bw.write("tick,epoch_ms,duration_ms,time_remaining_ns\n");
            bw.flush();
            running = true;
            writer = new Thread(() -> {
                try {
                    while (running || !queue.isEmpty()) {
                        String line = queue.poll();
                        if (line == null) {
                            Thread.sleep(5);
                            continue;
                        }
                        bw.write(line);
                        bw.newLine();
                    }
                    bw.flush();
                    bw.close();
                } catch (IOException | InterruptedException e) {
                    getLogger().severe("writer failed: " + e);
                }
            }, "ticklogger-writer");
            writer.setDaemon(true);
            writer.start();
        } catch (IOException e) {
            getLogger().severe("cannot open " + path + ": " + e);
            return;
        }
        getServer().getPluginManager().registerEvents(this, this);
        getLogger().info("logging per-tick durations to " + path);
    }

    @EventHandler
    public void onTickEnd(ServerTickEndEvent e) {
        queue.offer(e.getTickNumber() + "," + System.currentTimeMillis() + ","
                + e.getTickDuration() + "," + e.getTimeRemaining());
    }

    @Override
    public void onDisable() {
        running = false;
        try {
            if (writer != null) writer.join(5000);
        } catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
        }
    }
}
