// hc-gpu: Effect filter graph — Directed Acyclic Graph of processing nodes.
//
// Nodes are connected via typed ports. Execution order is determined by
// topological sort. Supports GPU shader backend (Phase 3).

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};

/// Unique identifier for a node in the filter graph.
pub type NodeId = usize;

/// Types of data flowing through filter graph ports.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum PortType {
    Video,
    Audio,
    Metadata,
}

/// Definition of an input or output port on a filter node.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Port {
    pub name: String,
    pub port_type: PortType,
}

/// A node in the effect filter graph.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilterNode {
    pub id: NodeId,
    pub name: String,
    pub node_type: FilterNodeType,
    pub inputs: Vec<Port>,
    pub outputs: Vec<Port>,
    /// Serialized parameters (JSON).
    pub parameters: String,
}

/// Types of filter nodes supported by the engine.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum FilterNodeType {
    /// Video source input.
    Source,
    /// Final output sink.
    Sink,
    /// Brightness, contrast, saturation, hue adjustment.
    ColorAdjust,
    /// Gaussian blur (separable kernel).
    Blur,
    /// Unsharp mask sharpen.
    Sharpen,
    /// 3D color lookup table (.cube format).
    Lut3D,
    /// Image/text overlay.
    Overlay,
    /// Resolution scaling.
    Scale,
    /// Fade to/from black transition.
    FadeTransition,
    /// Crossfade between two inputs.
    Crossfade,
    /// Speed ramp (time remapping).
    SpeedRamp,
}

/// Directed edge between two filter nodes.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilterEdge {
    pub from_node: NodeId,
    pub from_port: String,
    pub to_node: NodeId,
    pub to_port: String,
}

/// Complete filter graph DAG.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilterGraph {
    pub nodes: Vec<FilterNode>,
    pub edges: Vec<FilterEdge>,
}

impl FilterGraph {
    /// Create an empty filter graph.
    pub fn new() -> Self {
        FilterGraph {
            nodes: Vec::new(),
            edges: Vec::new(),
        }
    }

    /// Add a node and return its assigned ID.
    pub fn add_node(&mut self, node: FilterNode) -> NodeId {
        let id = self.nodes.len();
        let mut node = node;
        node.id = id;
        self.nodes.push(node);
        id
    }

    /// Add a directed edge between two ports.
    pub fn add_edge(&mut self, edge: FilterEdge) -> Result<(), String> {
        // Validate nodes exist
        if edge.from_node >= self.nodes.len() || edge.to_node >= self.nodes.len() {
            return Err("Edge references nonexistent node".into());
        }
        // Check for cycles by attempting topological sort
        let mut test_edges = self.edges.clone();
        test_edges.push(edge.clone());
        Self::topological_sort_inner(&self.nodes, &test_edges)?;
        self.edges.push(edge);
        Ok(())
    }

    /// Perform topological sort and return execution order.
    /// Returns error if the graph contains a cycle.
    pub fn execution_order(&self) -> Result<Vec<NodeId>, String> {
        Self::topological_sort_inner(&self.nodes, &self.edges)
    }

    fn topological_sort_inner(
        nodes: &[FilterNode],
        edges: &[FilterEdge],
    ) -> Result<Vec<NodeId>, String> {
        let mut in_degree: HashMap<NodeId, usize> = HashMap::new();
        let mut adjacency: HashMap<NodeId, Vec<NodeId>> = HashMap::new();

        for node in nodes {
            in_degree.entry(node.id).or_insert(0);
            adjacency.entry(node.id).or_default();
        }

        for edge in edges {
            *in_degree.entry(edge.to_node).or_insert(0) += 1;
            adjacency
                .entry(edge.from_node)
                .or_default()
                .push(edge.to_node);
        }

        let mut queue: VecDeque<NodeId> = in_degree
            .iter()
            .filter(|(_, &deg)| deg == 0)
            .map(|(&id, _)| id)
            .collect();

        let mut order = Vec::new();

        while let Some(node) = queue.pop_front() {
            order.push(node);
            if let Some(neighbors) = adjacency.get(&node) {
                for &neighbor in neighbors {
                    if let Some(deg) = in_degree.get_mut(&neighbor) {
                        *deg -= 1;
                        if *deg == 0 {
                            queue.push_back(neighbor);
                        }
                    }
                }
            }
        }

        if order.len() != nodes.len() {
            return Err("Graph contains a cycle".into());
        }

        Ok(order)
    }
}

impl Default for FilterGraph {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_test_node(id: NodeId) -> FilterNode {
        FilterNode {
            id,
            name: format!("node_{id}"),
            node_type: FilterNodeType::ColorAdjust,
            inputs: vec![],
            outputs: vec![],
            parameters: "{}".into(),
        }
    }

    #[test]
    fn test_empty_graph() {
        let graph = FilterGraph::new();
        assert!(graph.execution_order().unwrap().is_empty());
    }

    #[test]
    fn test_linear_chain() {
        let mut graph = FilterGraph::new();
        let a = graph.add_node(make_test_node(0));
        let b = graph.add_node(make_test_node(1));
        let c = graph.add_node(make_test_node(2));

        graph.add_edge(FilterEdge { from_node: a, from_port: "out".into(), to_node: b, to_port: "in".into() }).unwrap();
        graph.add_edge(FilterEdge { from_node: b, from_port: "out".into(), to_node: c, to_port: "in".into() }).unwrap();

        let order = graph.execution_order().unwrap();
        assert_eq!(order, vec![0, 1, 2]);
    }

    #[test]
    fn test_cycle_detection() {
        let mut graph = FilterGraph::new();
        let a = graph.add_node(make_test_node(0));
        let b = graph.add_node(make_test_node(1));

        graph.add_edge(FilterEdge { from_node: a, from_port: "out".into(), to_node: b, to_port: "in".into() }).unwrap();
        let result = graph.add_edge(FilterEdge { from_node: b, from_port: "out".into(), to_node: a, to_port: "in".into() });
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("cycle"));
    }

    #[test]
    fn test_diamond_dag() {
        let mut graph = FilterGraph::new();
        let a = graph.add_node(make_test_node(0));
        let b = graph.add_node(make_test_node(1));
        let c = graph.add_node(make_test_node(2));
        let d = graph.add_node(make_test_node(3));

        graph.add_edge(FilterEdge { from_node: a, from_port: "out".into(), to_node: b, to_port: "in".into() }).unwrap();
        graph.add_edge(FilterEdge { from_node: a, from_port: "out".into(), to_node: c, to_port: "in".into() }).unwrap();
        graph.add_edge(FilterEdge { from_node: b, from_port: "out".into(), to_node: d, to_port: "in".into() }).unwrap();
        graph.add_edge(FilterEdge { from_node: c, from_port: "out".into(), to_node: d, to_port: "in".into() }).unwrap();

        let order = graph.execution_order().unwrap();
        assert_eq!(order.len(), 4);
        assert_eq!(order[0], 0); // source first
        assert_eq!(order[3], 3); // sink last
    }
}
